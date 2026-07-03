#!/usr/bin/env python3
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
ARTIFACT_DIR = ROOT / "devtools" / "reports" / "benchmark_artifacts" / "acceptance_latency"
RESULTS_PATH = ARTIFACT_DIR / "results.json"
REPORT_PATH = ARTIFACT_DIR / "benchmark_report.md"

def main():
    if not RESULTS_PATH.exists():
        print(f"Error: {RESULTS_PATH} does not exist.")
        sys.exit(1)
        
    with RESULTS_PATH.open("r") as f:
        results = json.load(f)
        
    total = len(results)
    passed = sum(1 for r in results if r["pass"])
    
    # Calculate latency stats for passed/successful cases
    latencies = [r["acceptToFullInsertedMs"] for r in results if r["pass"] and r["acceptToFullInsertedMs"] > 0]
    latencies.sort()
    
    p50 = 0.0
    p90 = 0.0
    max_lat = 0.0
    if latencies:
        n = len(latencies)
        p50 = latencies[int(n * 0.5)]
        p90 = latencies[int(n * 0.9)]
        max_lat = latencies[-1]
        
    any_letter_by_letter = any(r["perCharacterFallback"] for r in results)
    
    verdict = "PASS" if passed == total else "FAIL"
    
    report_lines = [
        "# Acceptance Latency Benchmark Report",
        f"**Verdict:** {verdict}",
        "",
        f"- Total Cases: {total}",
        f"- Passed Cases: {passed}",
        f"- Failed Cases: {total - passed}",
        f"- p50 Latency (atomic only): {p50:.1f}ms",
        f"- p90 Latency (atomic only): {p90:.1f}ms",
        f"- Max Latency (atomic only): {max_lat:.1f}ms",
        f"- Any letter-by-character fallback occurred: {any_letter_by_letter}",
        "",
        "## Case Details",
        "| Case | Prefix | Displayed Completion | Accepted Text | Method | First Ms | Full Ms | Atomic | Char Fallback | Pass | Fail Reason |",
        "|---|---|---|---|---|---|---|---|---|---|---|",
    ]
    
    for r in results:
        prefix_display = r["prefix"].replace("\n", "\\n")
        disp_display = r["displayedCompletion"].replace("\n", "\\n")
        acc_display = r["acceptedText"].replace("\n", "\\n")
        
        report_lines.append(
            f"| {r['case']} | `{prefix_display}` | `{disp_display}` | `{acc_display}` | {r['insertionMethod']} | "
            f"{r['acceptToFirstInsertedMs']:.1f} | {r['acceptToFullInsertedMs']:.1f} | {r['insertedAtomically']} | "
            f"{r['perCharacterFallback']} | {r['pass']} | {r['failReason']} |"
        )
        
    report = "\n".join(report_lines)
    REPORT_PATH.write_text(report, encoding="utf-8")
    
    print("Acceptance report successfully written.")
    print(report)

if __name__ == "__main__":
    main()
