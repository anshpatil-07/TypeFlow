#!/usr/bin/env python3
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
ARTIFACT_DIR = ROOT / "devtools" / "reports" / "benchmark_artifacts" / "acceptance_behavior"
RESULTS_PATH = ARTIFACT_DIR / "results.json"
REPORT_PATH = ARTIFACT_DIR / "benchmark_report.md"

def main():
    if not RESULTS_PATH.exists():
        print(f"Error: {RESULTS_PATH} does not exist.")
        sys.exit(1)
        
    with RESULTS_PATH.open("r") as f:
        results = json.load(f)
        
    # Latency evaluation
    latency_total = len(results.get("acceptance_latency", []))
    latency_passed = sum(1 for r in results.get("acceptance_latency", []) if r["pass"])
    
    # Word-by-word evaluation
    wbw_total = len(results.get("word_by_word", []))
    wbw_passed = sum(1 for r in results.get("word_by_word", []) if r["pass"])
    
    # Prefix consumption evaluation
    pc_total = len(results.get("prefix_consumption", []))
    pc_passed = sum(1 for r in results.get("prefix_consumption", []) if r["pass"])
    
    # Multiline safety evaluation
    ml_safe = results.get("multiline_safety", {})
    ml_pass = ml_safe.get("pass", False)
    
    overall_pass = (latency_passed == latency_total) and (wbw_passed == wbw_total) and (pc_passed == pc_total) and ml_pass
    verdict = "PASS" if overall_pass else "FAIL"
    
    report_lines = [
        "# Unified Acceptance Behavior Benchmark Report",
        f"**Verdict:** {verdict}",
        "",
        "## Part 1: Acceptance Latency Results",
        "| Case | Prefix | displayedCompletionBefore | acceptedChunk | displayedCompletionAfter | insertionMethod | acceptToFullInsertedMs | insertedAtomically | unrelatedTextChanged | Pass/Fail Reasons |",
        "|---|---|---|---|---|---|---|---|---|---|",
    ]
    
    for r in results.get("acceptance_latency", []):
        prefix_disp = r["prefix"].replace("\n", "\\n")
        before_disp = r["displayedCompletionBefore"].replace("\n", "\\n")
        chunk_disp = r["acceptedChunk"].replace("\n", "\\n")
        after_disp = r["displayedCompletionAfter"].replace("\n", "\\n")
        report_lines.append(
            f"| {r['case']} | `{prefix_disp}` | `{before_disp}` | `{chunk_disp}` | `{after_disp}` | "
            f"{r['insertionMethod']} | {r['acceptToFullInsertedMs']:.1f} | {r['insertedAtomically']} | "
            f"{r['unrelatedTextChanged']} | {'pass' if r['pass'] else r['failReason']} |"
        )
        
    report_lines.extend([
        "",
        "## Part 2: Word-by-Word Acceptance Results",
        "| Case | Step | displayedBefore | acceptedChunk | displayedAfter | editorTextAfter | Pass/Fail Reasons |",
        "|---|---|---|---|---|---|---|",
    ])
    
    for r in results.get("word_by_word", []):
        before_disp = r["displayedBefore"].replace("\n", "\\n")
        chunk_disp = r["acceptedChunk"].replace("\n", "\\n")
        after_disp = r["displayedAfter"].replace("\n", "\\n")
        editor_disp = r["editorTextAfter"].replace("\n", "\\n")
        report_lines.append(
            f"| {r['case']} | {r['step']} | `{before_disp}` | `{chunk_disp}` | `{after_disp}` | `{editor_disp}` | "
            f"{'pass' if r['pass'] else r['failReason']} |"
        )
        
    report_lines.extend([
        "",
        "## Part 3: Prefix-Consumption Results",
        "| typedCharOrString | displayedBefore | prefixMatched | displayedAfter | ghostStillVisible | acceptReady | Pass/Fail Reasons |",
        "|---|---|---|---|---|---|---|",
    ])
    
    for r in results.get("prefix_consumption", []):
        before_disp = r["displayedBefore"].replace("\n", "\\n")
        after_disp = r["displayedAfter"].replace("\n", "\\n")
        report_lines.append(
            f"| `{r['typedCharOrString']}` | `{before_disp}` | {r['prefixMatched']} | `{after_disp}` | {r['ghostStillVisible']} | "
            f"{r['acceptReady']} | {'pass' if r['pass'] else r['failReason']} |"
        )
        
    report_lines.extend([
        "",
        "## Part 4: Multi-Line Caret Safety Results",
        f"- **Line 1 Before:** `{ml_safe.get('line1Before', '')}`",
        f"- **Line 1 After:** `{ml_safe.get('line1After', '')}`",
        f"- **Line 4 Before:** `{ml_safe.get('line4Before', '')}`",
        f"- **Line 4 After:** `{ml_safe.get('line4After', '')}`",
        f"- **Accepted Chunk:** `{ml_safe.get('acceptedChunk', '')}`",
        f"- **Unrelated Text Changed:** `{ml_safe.get('unrelatedTextChanged', False)}`",
        f"- **Inserted at Correct Caret:** `{ml_safe.get('insertedAtCaretCorrect', False)}`",
        f"- **Safety Pass:** `{ml_pass}`",
        f"- **Fail Reason:** `{ml_safe.get('failReason', '')}`"
    ])
    
    report = "\n".join(report_lines)
    REPORT_PATH.write_text(report, encoding="utf-8")
    print("Acceptance report successfully written.")
    print(report)

if __name__ == "__main__":
    main()
