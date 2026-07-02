#!/usr/bin/env python3
"""Analyze TypeFlow Safari product benchmark results."""

from __future__ import annotations

import argparse
import json
import statistics
from collections import defaultdict
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent
FIXTURE_PATH = ROOT / "tests" / "fixtures" / "safari_product_benchmark_cases.json"
RESULTS_PATH = ROOT / "benchmark_artifacts" / "benchmark_results.json"
REPORT_PATH = ROOT / "benchmark_artifacts" / "benchmark_report.md"
RUNS_PER_CASE = 1
DEFAULT_MAX_LATENCY_MS = 220
ABSOLUTE_HARD_CEILING_MS = 250


VERDICTS = {
    "FINAL_PRODUCT_PASS",
    "PRODUCT_PASS_CONTEXT_AWARE_MISSING",
    "EMPTY_COMPLETION_FAIL",
    "VISIBLE_GHOST_FAIL",
    "TAB_ACCEPTANCE_FAIL",
    "LATENCY_FAIL",
    "BUILD_FAIL",
    "STARTUP_FAIL",
    "CONFIG_FAIL",
    "SAFARI_AUTOMATION_FAIL",
    "INVALID_BENCHMARK",
    "INCONCLUSIVE"
}


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def percentile(values: list[float], pct: float) -> float | None:
    if not values:
        return None
    values = sorted(values)
    if len(values) == 1:
        return values[0]
    rank = (len(values) - 1) * pct
    lower = int(rank)
    upper = min(lower + 1, len(values) - 1)
    fraction = rank - lower
    return values[lower] + (values[upper] - values[lower]) * fraction


def result_has_reason(result: dict[str, Any], token: str) -> bool:
    return token in str(result.get("failReason") or "")


def build_is_green(results_payload: dict[str, Any]) -> bool:
    build_status = results_payload.get("buildStatus") or {}
    status = str(build_status.get("status", "")).lower()
    tests = str(build_status.get("swiftTests", "")).lower()
    cli = str(build_status.get("cliXcodebuild", "")).lower()
    if status in {"pass", "passed", "green", "ok", "success"}:
        return True
    return tests in {"pass", "passed", "green", "ok", "success"} and cli in {"pass", "passed", "green", "ok", "success"}


def analyze(results_path: Path, report_path: Path) -> tuple[str, str]:
    fixture = load_json(FIXTURE_PATH)
    payload = load_json(results_path)
    cases = fixture["cases"]
    runs_per_case = int(payload.get("runsPerCase") or RUNS_PER_CASE)
    expected_total = len(cases) * runs_per_case
    results = payload.get("results") or []
    case_by_id = {case["id"]: case for case in cases}
    grouped: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for result in results:
        grouped[str(result.get("caseID"))].append(result)

    invalid_reasons: list[str] = []
    if not payload.get("fixtureUnchanged"):
        invalid_reasons.append("Fixture hash changed during benchmark run.")
    if payload.get("fixtureHashStart") != payload.get("fixtureHashEnd"):
        invalid_reasons.append("Fixture hash start/end mismatch.")
    if len(results) != expected_total and not payload.get("abortedEarly"):
        invalid_reasons.append(f"Result count {len(results)} does not equal fixture cases * runsPerCase ({expected_total}).")
    if runs_per_case < 1:
        invalid_reasons.append("runsPerCase must be at least 1.")
    if payload.get("defaultMaxLatencyMs") != DEFAULT_MAX_LATENCY_MS:
        invalid_reasons.append("defaultMaxLatencyMs changed dynamically.")
    if payload.get("absoluteHardCeilingMs") != ABSOLUTE_HARD_CEILING_MS:
        invalid_reasons.append("absoluteHardCeilingMs changed dynamically.")
    for case in cases:
        runs = grouped.get(case["id"], [])
        run_indexes = sorted(result.get("runIndex") for result in runs)
        expected_indexes = list(range(1, runs_per_case + 1))
        if not payload.get("abortedEarly") and (len(runs) != runs_per_case or run_indexes != expected_indexes):
            invalid_reasons.append(f"{case['id']} does not include exactly runs {expected_indexes}.")
    for result in results:
        if str(result.get("caseID")) not in case_by_id:
            invalid_reasons.append(f"Unknown caseID {result.get('caseID')!r} appears in results.")

    all_failures = [result for result in results if not result.get("pass")]
    non_context_results = [
        result for result in results
        if not case_by_id.get(str(result.get("caseID")), {}).get("contextAwarenessRequired")
    ]
    context_results = [
        result for result in results
        if case_by_id.get(str(result.get("caseID")), {}).get("contextAwarenessRequired")
    ]
    passed_latencies = [
        float(result["totalPauseToVisibleMs"])
        for result in results
        if result.get("pass") and isinstance(result.get("totalPauseToVisibleMs"), (int, float))
    ]
    p90_latency = percentile(passed_latencies, 0.90)
    max_latency = max(passed_latencies) if passed_latencies else None

    unstable_cases = []
    if not payload.get("abortedEarly"):
        for case in cases:
            runs = grouped.get(case["id"], [])
            passed_count = sum(1 for result in runs if result.get("pass"))
            if passed_count != runs_per_case:
                unstable_cases.append((case["id"], passed_count))

    verdict = determine_verdict(
        payload,
        invalid_reasons,
        all_failures,
        non_context_results,
        context_results,
        p90_latency,
        max_latency,
        unstable_cases
    )
    report = render_report(
        verdict,
        fixture,
        payload,
        invalid_reasons,
        grouped,
        unstable_cases,
        p90_latency,
        max_latency
    )
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(report, encoding="utf-8")
    return verdict, report


def determine_verdict(
    payload: dict[str, Any],
    invalid_reasons: list[str],
    all_failures: list[dict[str, Any]],
    non_context_results: list[dict[str, Any]],
    context_results: list[dict[str, Any]],
    p90_latency: float | None,
    max_latency: float | None,
    unstable_cases: list[tuple[str, int]]
) -> str:
    if invalid_reasons:
        return "INVALID_BENCHMARK"
    if any(result_has_reason(result, "BUILD_FAIL") for result in all_failures) or not build_is_green(payload):
        return "BUILD_FAIL"
    abort_reason = str(payload.get("abortReason") or "")
    if payload.get("abortedEarly") and abort_reason.startswith("SAFARI_AUTOMATION_FAIL"):
        return "SAFARI_AUTOMATION_FAIL"
    startup_status = payload.get("startupStatus") or {}
    if str(startup_status.get("status", "")).lower() not in {"pass", "passed", "green", "ok", "success"}:
        return "STARTUP_FAIL"
    if not startup_status.get("modelReady"):
        return "CONFIG_FAIL"
    if payload.get("abortedEarly") and "Safari automation" in abort_reason:
        return "INCONCLUSIVE"
    if any(result_has_reason(result, "TAB_ACCEPTANCE_FAIL") for result in all_failures):
        return "TAB_ACCEPTANCE_FAIL"
    if any(result_has_reason(result, "EMPTY_COMPLETION_FAIL") for result in non_context_results):
        return "EMPTY_COMPLETION_FAIL"
    if any(result_has_reason(result, "VISIBLE_GHOST_FAIL") for result in all_failures):
        return "VISIBLE_GHOST_FAIL"
    if any(result_has_reason(result, "LATENCY_FAIL") for result in all_failures):
        return "LATENCY_FAIL"
    if p90_latency is None or max_latency is None:
        return "INCONCLUSIVE"
    if p90_latency > DEFAULT_MAX_LATENCY_MS:
        return "LATENCY_FAIL"
    repeated_hard_ceiling = sum(
        1 for result in all_failures
        if isinstance(result.get("totalPauseToVisibleMs"), (int, float))
        and float(result["totalPauseToVisibleMs"]) > ABSOLUTE_HARD_CEILING_MS
    )
    if repeated_hard_ceiling > 1:
        return "LATENCY_FAIL"
    non_context_pass = all(result.get("pass") for result in non_context_results)
    context_failures = [result for result in context_results if not result.get("pass")]
    context_missing = (
        non_context_pass
        and context_failures
        and all(
            str(result.get("contextSource") or "").lower() in {"focusededitoronly", "focused_editor_only", ""}
            or "context" in str(result.get("failReason") or "").lower()
            for result in context_failures
        )
    )
    if context_missing:
        return "PRODUCT_PASS_CONTEXT_AWARE_MISSING"
    if unstable_cases:
        return "INCONCLUSIVE"
    if all_failures:
        return "INCONCLUSIVE"
    if max_latency > ABSOLUTE_HARD_CEILING_MS:
        return "LATENCY_FAIL"
    return "FINAL_PRODUCT_PASS"


def render_report(
    verdict: str,
    fixture: dict[str, Any],
    payload: dict[str, Any],
    invalid_reasons: list[str],
    grouped: dict[str, list[dict[str, Any]]],
    unstable_cases: list[tuple[str, int]],
    p90_latency: float | None,
    max_latency: float | None
) -> str:
    lines: list[str] = []
    lines.append("# Safari Product Benchmark Report")
    lines.append("")
    lines.append(f"Verdict: **{verdict}**")
    lines.append("")
    lines.append("## Integrity")
    lines.append("")
    lines.append(f"- Fixture start hash: `{payload.get('fixtureHashStart', '')}`")
    lines.append(f"- Fixture end hash: `{payload.get('fixtureHashEnd', '')}`")
    lines.append(f"- Fixture unchanged: `{payload.get('fixtureUnchanged')}`")
    lines.append(f"- Runs per case: `{payload.get('runsPerCase')}`")
    lines.append(f"- Observation window: `{payload.get('observationWindowMs')}ms`")
    lines.append(f"- Default pass latency: `{payload.get('defaultMaxLatencyMs')}ms`")
    lines.append(f"- Absolute hard ceiling: `{payload.get('absoluteHardCeilingMs')}ms`")
    lines.append(f"- Aborted early: `{payload.get('abortedEarly', False)}`")
    if payload.get("abortReason"):
        lines.append(f"- Abort reason: `{payload.get('abortReason')}`")
    if invalid_reasons:
        lines.append("")
        lines.append("Invalid benchmark reasons:")
        for reason in invalid_reasons:
            lines.append(f"- {reason}")
    lines.append("")
    lines.append("## Build And Startup")
    lines.append("")
    lines.append(f"- Build status: `{json.dumps(payload.get('buildStatus', {}), sort_keys=True)}`")
    lines.append(f"- Startup status: `{json.dumps(payload.get('startupStatus', {}), sort_keys=True)}`")
    if payload.get("safariAutomationSmoke"):
        lines.append(f"- Safari automation smoke: `{json.dumps(payload.get('safariAutomationSmoke', {}), sort_keys=True)}`")
    lines.append(f"- Safari cleanup attempted: `{payload.get('safariCleanupAttempted', False)}`")
    lines.append("")
    lines.append("## Latency")
    lines.append("")
    lines.append(f"- Passed-run p90 totalPauseToVisibleMs: `{format_ms(p90_latency)}`")
    lines.append(f"- Passed-run max totalPauseToVisibleMs: `{format_ms(max_latency)}`")
    if unstable_cases:
        lines.append("")
        lines.append("Unstable or failing cases:")
        for case_id, passed_count in unstable_cases:
            lines.append(f"- `{case_id}` passed `{passed_count}/{payload.get('runsPerCase', RUNS_PER_CASE)}`")
    lines.append("")
    lines.append("## Case Runs")
    lines.append("")
    if payload.get("abortedEarly") and not any(grouped.values()):
        lines.append("Safari cases did not run.")
        lines.append("")
    lines.append("| Case | Run | Pass | Latency | Visible Ghost | Tab Match | Fail Reason | Screenshot |")
    lines.append("| --- | ---: | --- | ---: | --- | --- | --- | --- |")
    for case in fixture["cases"]:
        for result in sorted(grouped.get(case["id"], []), key=lambda item: item.get("runIndex", 0)):
            visible = sanitize_table(str(result.get("visibleGhostText") or ""))
            reason = sanitize_table(str(result.get("failReason") or ""))
            screenshot = sanitize_table(str(result.get("screenshotPath") or ""))
            lines.append(
                f"| `{case['id']}` | {result.get('runIndex')} | `{result.get('pass')}` | "
                f"`{format_ms(result.get('totalPauseToVisibleMs'))}` | {visible} | "
                f"`{result.get('tabInsertedMatchesVisibleGhost')}` | {reason} | {screenshot} |"
            )
    lines.append("")
    lines.append("## Verdict Rules Applied")
    lines.append("")
    lines.append("- Failed cases are included; no case or run is dropped.")
    lines.append("- Cases must pass every scheduled run; repeated runs are not averaged away.")
    lines.append("- Fixture hashes must match from start to end.")
    lines.append("- 300ms is only the observation window; each case still uses maxLatencyMs, defaulting to 220ms.")
    lines.append("- Empty completions, invisible ghost text, stale Tab acceptance, and mismatched Tab insertion are failures.")
    return "\n".join(lines) + "\n"


def format_ms(value: Any) -> str:
    if isinstance(value, (int, float)):
        return f"{float(value):.1f}ms"
    return "n/a"


def sanitize_table(value: str) -> str:
    compact = " ".join(value.split())
    compact = compact.replace("|", "\\|")
    if len(compact) > 120:
        return compact[:117] + "..."
    return compact


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Analyze Safari product benchmark results.")
    parser.add_argument("--results", default=str(RESULTS_PATH))
    parser.add_argument("--report", default=str(REPORT_PATH))
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    verdict, _ = analyze(Path(args.results), Path(args.report))
    if verdict not in VERDICTS:
        raise SystemExit(f"Unknown verdict {verdict}")
    print(verdict)
