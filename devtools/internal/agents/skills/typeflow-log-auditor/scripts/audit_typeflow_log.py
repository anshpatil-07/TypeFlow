#!/usr/bin/env python3
"""Audit TypeFlow logs and print a structured handoff report."""

import argparse
import os
import re
import sys
from collections import Counter, defaultdict


LATENCY_FIELDS = [
    "totalPauseToVisibleMs",
    "inputToDebounceMs",
    "contextMs",
    "axMs",
    "promptMs",
    "llamaFirstTokenMs",
    "llamaFirstUsableMs",
    "renderMs",
]

STAGE_MARKERS = {
    "Stage 4": ["[QualityAudit]"],
    "Stage 3": ["[RenderSchedule]", "[RenderPipeline]", "[GeometryProbe]", "[EditableResolver]"],
    "Stage 2": ["[DebounceAudit]", "[LatencySummary]", "[AXHotPath]", "[ModelReadiness]"],
    "Stage 1": ["[Stage1B]", "Stage1A", "Stage 1A", "Stage 1B"],
}

QUALITY_REASONS = [
    "validContinuation",
    "empty",
    "punctuationOnly",
    "duplicatePrefix",
    "assistantLike",
    "tooLong",
    "trailingWhitespace",
    "repeatedTokenLoop",
    "ocrContextContamination",
    "pureOverlap",
    "duplicatePrefixRemoval",
]


def usage():
    script = os.path.basename(sys.argv[0])
    print(f"Usage: python .agents/skills/typeflow-log-auditor/scripts/{script} [--compact] <log-file>")


def percentile(values, pct):
    if not values:
        return None
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    rank = (pct / 100.0) * (len(ordered) - 1)
    low = int(rank)
    high = min(low + 1, len(ordered) - 1)
    weight = rank - low
    return ordered[low] * (1 - weight) + ordered[high] * weight


def summarize_ms(values):
    if not values:
        return "missing"
    return (
        f"count={len(values)}, avg={sum(values) / len(values):.1f}, "
        f"p50={percentile(values, 50):.1f}, p90={percentile(values, 90):.1f}, "
        f"max={max(values):.1f}"
    )


def extract_float_field(line, field):
    match = re.search(
        rf"(?<![A-Za-z0-9_]){re.escape(field)}\s*(?:=|:)\s*([-+]?\d+(?:\.\d+)?)",
        line,
        re.IGNORECASE,
    )
    return float(match.group(1)) if match else None


def extract_quoted_field(line, field):
    match = re.search(rf"{re.escape(field)}='((?:\\'|[^'])*)'", line)
    if not match:
        return ""
    return match.group(1).replace("\\'", "'").replace("\\n", "\n").replace("\\t", "\t")


def extract_word_field(line, field):
    match = re.search(rf"(?<![A-Za-z0-9_]){re.escape(field)}=([^ ]+)", line)
    return match.group(1).strip().strip(",;]").strip() if match else ""


def add_example(examples, line, limit=10):
    text = line.rstrip("\n")
    if text and text not in examples and len(examples) < limit:
        examples.append(text)


def detect_stage(marker_counts):
    for stage in ["Stage 4", "Stage 3", "Stage 2", "Stage 1"]:
        if marker_counts[stage] > 0:
            confidence = "high" if marker_counts[stage] >= 3 else "medium"
            ambiguous = [name for name, count in marker_counts.items() if name != stage and count > 0]
            note = "ambiguous: also saw " + ", ".join(ambiguous) if ambiguous else "not ambiguous"
            return stage, confidence, note
    return "unknown", "low", "no known stage markers found"


def parse_log(path):
    data = {
        "path": path,
        "line_count": 0,
        "marker_counts": Counter(),
        "metrics": defaultdict(list),
        "render_pipeline_apply": [],
        "render_schedule_apply": [],
        "request_to_main": [],
        "request_to_apply": [],
        "deferred_wait": [],
        "stage": Counter(),
        "debounce": Counter(),
        "geometry": Counter(),
        "geometry_sources": Counter(),
        "resolver_sources": Counter(),
        "blocked_reasons": Counter(),
        "pending_drops": Counter(),
        "render_excluded": Counter(),
        "quality": Counter(),
        "quality_sources": Counter(),
        "quality_examples_rejected": [],
        "quality_examples_accepted": [],
        "suspicious_render_examples": [],
        "representative": [],
        "build": Counter(),
        "regressions": Counter(),
        "missing": set(),
    }

    last_quality_request = None
    saw_quality_total = 0

    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            data["line_count"] += 1
            lower = line.lower()

            for stage, markers in STAGE_MARKERS.items():
                if any(marker.lower() in lower for marker in markers):
                    data["marker_counts"][stage] += 1

            for field in LATENCY_FIELDS:
                value = extract_float_field(line, field)
                if value is not None:
                    data["metrics"][field].append(value)

            if "[latencysummary]" in lower and "cancelled=true" in lower:
                data["stage"]["cancelled LatencySummary"] += 1
            if "[latencysummary]" in lower and "cancelled=true" not in lower:
                data["stage"]["successful LatencySummary"] += 1

            if "swift test_overlap.swift" in lower:
                data["build"]["test_overlap mentioned"] += 1
            if "swift test_mem.swift" in lower:
                data["build"]["test_mem mentioned"] += 1
            if "** build succeeded **" in lower or "xcodebuild" in lower and "build succeeded" in lower:
                data["build"]["xcodebuild pass"] += 1
            if "build failed" in lower or "** build failed **" in lower:
                data["build"]["xcodebuild fail"] += 1
            if "instrumentation-only" in lower or "no-code-change" in lower or "no code change" in lower:
                data["build"]["instrumentation/no-code-change mentioned"] += 1

            if "stale completed discards" in lower or "stalecompleteddiscards" in lower:
                value = extract_float_field(line, "staleCompletedDiscards")
                if value is not None:
                    data["stage"]["Stage1A stale completed discards"] = max(data["stage"]["Stage1A stale completed discards"], int(value))
            if "stale visible blocks" in lower or "stalevisibleblocks" in lower:
                value = extract_float_field(line, "staleVisibleBlocks")
                if value is not None:
                    data["stage"]["Stage1A stale visible blocks"] = max(data["stage"]["Stage1A stale visible blocks"], int(value))
            if "blocked stale visible update" in lower:
                data["stage"]["Stage1A stale visible blocks"] += 1
                add_example(data["representative"], line)
            if "discarded completed stale generation" in lower:
                data["stage"]["Stage1A stale completed discards"] += 1
                add_example(data["representative"], line)
            if "[stage1b]" in lower and "cancellation requested" in lower:
                data["stage"]["Stage1B cancellation requests"] += 1
                add_example(data["representative"], line)
            if "[stage1b]" in lower and "abort callback triggered" in lower:
                data["stage"]["Stage1B abort callbacks"] += 1
                add_example(data["representative"], line)
            if "[stage1b]" in lower and "generation exited cancelled" in lower:
                data["stage"]["Stage1B cancelled exits"] += 1
            if "stale/cancelled stream token suppressed" in lower:
                data["stage"]["stale/cancelled stream suppression"] += 1

            if "[debounceaudit]" in lower and "scheduled" in lower:
                data["debounce"]["schedules"] += 1
            if "[debounceaudit]" in lower and "fired" in lower:
                data["debounce"]["fires"] += 1
            if "[debounceaudit]" in lower and "skipped" in lower:
                data["debounce"]["skips"] += 1
            if "gettextbeforecaret" in lower:
                data["stage"]["getTextBeforeCaret count"] += 1
            if "model is not ready yet. queuing request" in lower:
                data["stage"]["model readiness stuck queue"] += 1

            if "[renderpipeline]" in lower:
                duration = extract_float_field(line, "durationMs")
                if duration is not None:
                    data["render_pipeline_apply"].append(duration)
                layer_count = extract_float_field(line, "layerCountAfter")
                if layer_count is not None and layer_count > 1:
                    data["regressions"]["overlay layerCountAfter > 1"] += 1
                    add_example(data["suspicious_render_examples"], line)
            if "[overlaysrender]" in lower or "[overlayrender]" in lower:
                layer_count = extract_float_field(line, "layerCountAfter")
                if layer_count is not None and layer_count > 1:
                    data["regressions"]["overlay layerCountAfter > 1"] += 1
                    add_example(data["suspicious_render_examples"], line)
            if "[renderschedule]" in lower:
                apply_ms = extract_float_field(line, "applyMs")
                if apply_ms is not None:
                    data["render_schedule_apply"].append(apply_ms)
                delay_ms = extract_float_field(line, "delayMs")
                if "mainqueuestarted" in lower and delay_ms is not None:
                    data["request_to_main"].append(delay_ms)
                request_to_apply = extract_float_field(line, "requestToApplyMs")
                if request_to_apply is not None:
                    data["request_to_apply"].append(request_to_apply)
                wait_ms = extract_float_field(line, "waitMs")
                if ("deferredrenderflushed" in lower or "visibleapplyafterflush" in lower or "keydepthzeroflush" in lower) and wait_ms is not None:
                    data["deferred_wait"].append(wait_ms)
                if "blockedbyinputcriticalsection" in lower:
                    data["stage"]["blockedByInputCriticalSection"] += 1
                    reason = extract_word_field(line, "reason") or "unknown"
                    data["blocked_reasons"][reason] += 1
                    add_example(data["representative"], line)
                if "deferredrenderflushed" in lower:
                    data["stage"]["deferredRenderFlushed"] += 1
                if "pendingrenderreplaced" in lower:
                    data["stage"]["pending render replaced"] += 1
                if "pendingrenderdropped" in lower:
                    reason = extract_word_field(line, "reason") or "unknown"
                    data["pending_drops"][reason] += 1
                if "rendermsexcluded" in lower:
                    reason = extract_word_field(line, "reason") or "unknown"
                    data["render_excluded"][reason] += 1

            if "skipped render because geometry unavailable" in lower or "skippedrender novalidgeometry" in lower:
                data["geometry"]["geometry unavailable skips"] += 1
            if "focusedelementunavailable" in lower:
                data["geometry"]["focusedElementUnavailable"] += 1
            if "[geometryprobe]" in lower and "finalgeometry available=true" in lower:
                data["geometry"]["finalGeometry true"] += 1
                source = extract_word_field(line, "source") or "unknown"
                data["geometry_sources"][source] += 1
            if "[geometryprobe]" in lower and "finalgeometry available=false" in lower:
                data["geometry"]["finalGeometry false"] += 1
            if "[editableresolver]" in lower and "resolved source=" in lower:
                data["geometry"]["EditableResolver success"] += 1
                source = extract_word_field(line, "source") or "unknown"
                data["resolver_sources"][source] += 1

            if "swallowed=true" in lower:
                data["regressions"]["swallowed=true"] += 1
            if "originalreturned=false" in lower:
                data["regressions"]["originalReturned=false"] += 1
            if "accepttapinstallms" in lower and "ordinary" in lower:
                data["regressions"]["accept tap installed during ordinary typing"] += 1
            if "model is not ready yet. queuing request" in lower:
                data["regressions"]["Model is not ready yet. Queuing request"] += 1

            if "[qualityaudit] requestid=" in lower:
                saw_quality_total += 1
                last_quality_request = {
                    "requestID": extract_word_field(line, "requestID"),
                    "phase": extract_word_field(line, "phase"),
                    "textBeforeCaret": extract_quoted_field(line, "textBeforeCaret"),
                    "rawOutput": extract_quoted_field(line, "rawOutput"),
                    "processedOutput": extract_quoted_field(line, "processedOutput"),
                    "accepted": extract_word_field(line, "accepted"),
                    "rejectionReason": extract_word_field(line, "rejectionReason"),
                }
            elif "[qualityaudit] reason=" in lower:
                reason = extract_word_field(line, "reason") or "unknown"
                source = extract_word_field(line, "source") or "unknown"
                active_line = extract_quoted_field(line, "activeLine")
                final_suggestion = extract_quoted_field(line, "finalSuggestion")
                data["quality"][reason] += 1
                data["quality_sources"][source] += 1
                example = dict(last_quality_request or {})
                example.update({"reason": reason, "source": source, "activeLine": active_line, "finalSuggestion": final_suggestion})
                if reason == "validContinuation":
                    if len(data["quality_examples_accepted"]) < 5:
                        data["quality_examples_accepted"].append(example)
                else:
                    if len(data["quality_examples_rejected"]) < 10:
                        data["quality_examples_rejected"].append(example)

            if "ordinary ordinary" in lower or re.search(r"\b([A-Za-z]{3,})\b(?:\s+\1\b){2,}", line, re.IGNORECASE):
                data["quality"]["repeatedTokenLoop"] += 1
                data["quality"]["repeated-word/render contamination"] += 1
                add_example(data["suspicious_render_examples"], line)

    data["quality"]["total records"] = saw_quality_total
    return data


def table(counter, keys):
    rows = ["| Signal | Count |", "| --- | ---: |"]
    for key in keys:
        rows.append(f"| {key} | {counter.get(key, 0)} |")
    return "\n".join(rows)


def counter_table(counter, title):
    print(f"### {title}")
    if not counter:
        print("missing\n")
        return
    print("| Signal | Count |")
    print("| --- | ---: |")
    for key, count in counter.most_common():
        print(f"| {key} | {count} |")
    print()


def metric_table(data, fields):
    print("| Field | Summary ms |")
    print("| --- | --- |")
    for field, values in fields:
        print(f"| {field} | {summarize_ms(values)} |")
    print()


def validation_signal(build, key):
    if key == "xcodebuild":
        if build["xcodebuild fail"]:
            return "fail"
        if build["xcodebuild pass"]:
            return "pass"
        return "unknown"
    return "mentioned" if build[f"{key} mentioned"] else "unknown"


def print_examples(title, examples, limit=5):
    print(f"### {title}")
    if not examples:
        print("missing\n")
        return
    for example in examples[:limit]:
        if isinstance(example, dict):
            print(f"- requestID={example.get('requestID', '')} source={example.get('source', '')} reason={example.get('reason', '')}")
            print(f"  activeLine: `{one_line(example.get('activeLine', ''))}`")
            print(f"  rawOutput: `{one_line(example.get('rawOutput', ''))}`")
            print(f"  processedOutput: `{one_line(example.get('processedOutput', ''))}`")
            print(f"  finalSuggestion: `{one_line(example.get('finalSuggestion', ''))}`")
        else:
            print(f"- `{one_line(example)}`")
    print()


def one_line(text, limit=180):
    text = str(text).replace("\n", "\\n").replace("\t", "\\t")
    return text if len(text) <= limit else "..." + text[-limit:]


def diagnosis(data):
    notes = []
    metrics = data["metrics"]
    q = data["quality"]
    stage = data["stage"]
    geom = data["geometry"]
    regressions = data["regressions"]

    if metrics["llamaFirstUsableMs"] and metrics["totalPauseToVisibleMs"]:
        if sum(metrics["llamaFirstUsableMs"]) / len(metrics["llamaFirstUsableMs"]) < 60 and sum(metrics["totalPauseToVisibleMs"]) / len(metrics["totalPauseToVisibleMs"]) > 180:
            notes.append("llamaFirstUsableMs is low while totalPauseToVisibleMs is high; bottleneck is likely scheduling/render/debounce, not the model.")
    if data["render_pipeline_apply"] and metrics["renderMs"]:
        if sum(data["render_pipeline_apply"]) / len(data["render_pipeline_apply"]) < 10 and sum(metrics["renderMs"]) / len(metrics["renderMs"]) > 30:
            notes.append("RenderPipeline apply is low while renderMs is high; bottleneck is likely render scheduling/deferral.")
    if geom["focusedElementUnavailable"] or geom["finalGeometry false"] or geom["geometry unavailable skips"]:
        notes.append("Geometry failures are present; investigate caret geometry extraction before caching or render tuning.")
    if q["punctuationOnly"] or q["pureOverlap"] or q["empty"] or q["repeated-word/render contamination"]:
        notes.append("Quality issues point to continuation post-processing/token healing rather than model speed.")
    if q["assistantLike"]:
        notes.append("Assistant-like outputs are present; prompt/model mode may be wrong.")
    if stage["model readiness stuck queue"] or regressions["Model is not ready yet. Queuing request"]:
        notes.append("Model readiness queueing is present; model readiness gating may be broken.")
    if regressions["swallowed=true"] or regressions["originalReturned=false"]:
        notes.append("Input hijack regression signal is nonzero; fix this before further optimization.")
    if regressions["overlay layerCountAfter > 1"]:
        notes.append("Overlay layer accumulation signal is nonzero; verify Stage 3A idempotent rendering did not regress.")
    return notes or ["No strong heuristic diagnosis from available metrics; inspect missing metrics and representative examples."]


def recommendation(data):
    q = data["quality"]
    geom = data["geometry"]
    regressions = data["regressions"]
    stage = data["stage"]
    if regressions["swallowed=true"] or regressions["originalReturned=false"]:
        return "Do not optimize; fix input hijack regression first."
    if stage["model readiness stuck queue"] or regressions["Model is not ready yet. Queuing request"]:
        return "Fix model readiness gating before latency or quality work."
    if geom["focusedElementUnavailable"] or geom["geometry unavailable skips"]:
        return "Investigate geometry resolver before caching or render scheduling changes."
    if q["punctuationOnly"] or q["empty"] or q["pureOverlap"] or q["repeated-word/render contamination"]:
        return "Proceed with continuation post-processing contract fix; do not change model/prompt yet."
    return "Continue with the smallest stage-specific experiment supported by the metrics."


def missing_metrics(data):
    missing = []
    for field in LATENCY_FIELDS:
        if not data["metrics"][field]:
            missing.append(field)
    for name, counter, keys in [
        ("Stage1", data["stage"], ["Stage1A stale completed discards", "Stage1A stale visible blocks", "Stage1B abort callbacks"]),
        ("Geometry", data["geometry"], ["finalGeometry true", "focusedElementUnavailable", "geometry unavailable skips"]),
        ("Quality", data["quality"], ["total records"]),
    ]:
        for key in keys:
            if counter.get(key, 0) == 0:
                missing.append(f"{name}: {key}")
    return missing


def render_full(data):
    stage, confidence, ambiguity = detect_stage(data["marker_counts"])
    print("# TypeFlow Log Audit\n")
    print("## 1. Log metadata")
    print(f"- log file: `{data['path']}`")
    print(f"- line count: {data['line_count']}")
    print(f"- detected stage: {stage}")
    print(f"- detected stage confidence / top markers: {confidence}; {dict(data['marker_counts'])}")
    print(f"- ambiguity note: {ambiguity}\n")

    print("## 2. Validation/build signals, if present")
    print(f"- swift test_overlap.swift: {validation_signal(data['build'], 'test_overlap')}")
    print(f"- swift test_mem.swift: {validation_signal(data['build'], 'test_mem')}")
    print(f"- xcodebuild: {validation_signal(data['build'], 'xcodebuild')}")
    print(f"- no-code-change / instrumentation-only mentions: {data['build']['instrumentation/no-code-change mentioned']}\n")

    print("## 3. Stage-specific metrics")
    print("### Stage 1")
    print(table(data["stage"], [
        "Stage1A stale completed discards",
        "Stage1A stale visible blocks",
        "Stage1B cancellation requests",
        "Stage1B abort callbacks",
        "Stage1B cancelled exits",
        "stale/cancelled stream suppression",
    ]))
    print()

    print("### Stage 2")
    print(table(data["stage"], [
        "successful LatencySummary",
        "cancelled LatencySummary",
        "getTextBeforeCaret count",
        "model readiness stuck queue",
    ]))
    metric_table(data, [(field, data["metrics"][field]) for field in LATENCY_FIELDS])
    print(table(data["debounce"], ["schedules", "fires", "skips"]))
    print()

    print("### Stage 3")
    metric_table(data, [
        ("totalPauseToVisibleMs", data["metrics"]["totalPauseToVisibleMs"]),
        ("renderMs", data["metrics"]["renderMs"]),
        ("RenderPipeline apply duration", data["render_pipeline_apply"]),
        ("RenderSchedule apply duration", data["render_schedule_apply"]),
        ("render request to main start", data["request_to_main"]),
        ("render request to apply", data["request_to_apply"]),
        ("deferred wait", data["deferred_wait"]),
    ])
    print(table(data["stage"], [
        "blockedByInputCriticalSection",
        "deferredRenderFlushed",
        "pending render replaced",
    ]))
    print()
    counter_table(data["blocked_reasons"], "Blocked reason breakdown")
    counter_table(data["pending_drops"], "Pending render dropped breakdown")
    counter_table(data["render_excluded"], "renderMsExcluded breakdown")
    print(table(data["geometry"], [
        "geometry unavailable skips",
        "finalGeometry true",
        "finalGeometry false",
        "focusedElementUnavailable",
        "EditableResolver success",
    ]))
    print()
    counter_table(data["geometry_sources"], "Geometry source breakdown")
    counter_table(data["resolver_sources"], "Resolver source breakdown")

    print("### Stage 4")
    print(table(data["quality"], [
        "total records",
        "validContinuation",
        "empty",
        "punctuationOnly",
        "duplicatePrefix",
        "assistantLike",
        "tooLong",
        "trailingWhitespace",
        "repeatedTokenLoop",
        "ocrContextContamination",
        "pureOverlap",
        "duplicatePrefixRemoval",
        "repeated-word/render contamination",
    ]))
    print()
    counter_table(data["quality_sources"], "Quality source breakdown")

    print("## 4. Regression signals")
    regression = Counter(data["regressions"])
    regression["focusedElementUnavailable"] = data["geometry"]["focusedElementUnavailable"]
    regression["geometry unavailable skip"] = data["geometry"]["geometry unavailable skips"]
    regression["stale visible blocks"] = data["stage"]["Stage1A stale visible blocks"]
    regression["stale completed discards"] = data["stage"]["Stage1A stale completed discards"]
    print(table(regression, [
        "swallowed=true",
        "originalReturned=false",
        "accept tap installed during ordinary typing",
        "overlay layerCountAfter > 1",
        "focusedElementUnavailable",
        "geometry unavailable skip",
        "Model is not ready yet. Queuing request",
        "stale visible blocks",
        "stale completed discards",
    ]))
    print()

    print("## 5. Representative examples")
    print_examples("Top rejected examples", data["quality_examples_rejected"], 5)
    print_examples("Top accepted examples", data["quality_examples_accepted"], 3)
    print_examples("Suspicious render examples", data["suspicious_render_examples"], 3)
    raw_examples = data["representative"][:10]
    print_examples("Representative raw lines", raw_examples, 10)

    print("## 6. Diagnosis")
    for note in diagnosis(data):
        print(f"- {note}")
    print()

    print("## 7. Recommended next step")
    print(f"- {recommendation(data)}\n")

    print("## 8. Missing metrics")
    missing = missing_metrics(data)
    if missing:
        for item in missing:
            print(f"- {item}")
    else:
        print("- none")


def render_compact(data):
    stage, confidence, ambiguity = detect_stage(data["marker_counts"])
    print("# TypeFlow Log Audit Compact")
    print(f"- log file: `{data['path']}`")
    print(f"- lines scanned: {data['line_count']}")
    print(f"- stage detected: {stage} ({confidence}; {ambiguity})")
    print(f"- totalPauseToVisibleMs: {summarize_ms(data['metrics']['totalPauseToVisibleMs'])}")
    print(f"- renderMs: {summarize_ms(data['metrics']['renderMs'])}")
    print(f"- QualityAudit records: {data['quality']['total records']}")
    print(f"- valid/empty/punctuation: {data['quality']['validContinuation']}/{data['quality']['empty']}/{data['quality']['punctuationOnly']}")
    print(f"- overlay layerCountAfter > 1: {data['regressions']['overlay layerCountAfter > 1']}")
    print(f"- swallowed=true: {data['regressions']['swallowed=true']}")
    print(f"- recommendation: {recommendation(data)}")


def main():
    parser = argparse.ArgumentParser(add_help=True)
    parser.add_argument("--compact", action="store_true", help="print a short summary instead of the full handoff report")
    parser.add_argument("log_file", nargs="?")
    args = parser.parse_args()

    if not args.log_file:
        usage()
        return 0
    if not os.path.exists(args.log_file):
        print(f"Error: log file not found: {args.log_file}", file=sys.stderr)
        return 2

    data = parse_log(args.log_file)
    if args.compact:
        render_compact(data)
    else:
        render_full(data)
    return 0


if __name__ == "__main__":
    sys.exit(main())
