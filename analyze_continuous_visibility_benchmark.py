#!/usr/bin/env python3
import json
import statistics
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent
ARTIFACT_DIR = ROOT / "benchmark_artifacts" / "continuous_visibility"
RESULTS_PATH = ARTIFACT_DIR / "results.jsonl"
REPORT_PATH = ARTIFACT_DIR / "benchmark_report.md"

def load_results():
    if not RESULTS_PATH.exists():
        return []
    with open(RESULTS_PATH, "r") as f:
        return [json.loads(line) for line in f if line.strip()]

def evaluate_quality(result):
    text = result.get("visibleGhostText", "").strip()
    latency = result.get("latencyMs")
    
    if not text:
        return "invisible", ["Ghost text invisible or empty"]
        
    if latency is not None and latency > 220:
        return "late", [f"Latency {latency}ms > 220ms target"]
        
    words = text.split()
    word_count = len(words)
    
    prefix = result.get("typedPrefix", "").strip()
    prefix_words = prefix.split()
    
    reasons = []
    
    if re.search(r'(<[^>]+>|```|^\s*[-*]\s|^\s*\d+\.\s)', text):
        return "markup_or_list", ["Contains markup or list markers"]
        
    if len(prefix_words) >= 3 and len(words) >= 3:
        last_typed = " ".join(prefix_words[-3:]).lower()
        suggested_start = " ".join(words[:3]).lower()
        if last_typed == suggested_start:
            return "repeat", [f"Repeats recently typed text: '{last_typed}'"]
            
    if len(prefix_words) >= 2 and len(words) >= 2:
        sentence_start = prefix_words[0].lower() if prefix_words else ""
        if sentence_start and words[0].lower() == sentence_start:
            if " ".join(words[:2]).lower() == " ".join(prefix_words[:2]).lower():
                return "restart", ["Appears to restart the sentence"]
                
    if word_count > 6:
        return "too_long", [f"{word_count} words > 6 limit"]
        
    if word_count < 2:
        return "too_short", [f"{word_count} word (acceptable if early)"]
        
    return "likely_good", []

def analyze():
    results = load_results()
    if not results:
        print("No results found.")
        return
        
    continuous = [r for r in results if r.get("scenario") == "continuous"]
    divergence = [r for r in results if r.get("scenario") == "divergence"]
    
    total = len(continuous)
    
    # Evaluate strict actualUserVisible for all continuous checkpoints
    for r in continuous:
        vis_text = r.get("visibleGhostText", "").strip()
        render_committed = r.get("renderCommitted", False)
        overlay_visible = r.get("overlayVisible", False)
        commit_failed = r.get("commitFailed", False)
        layer_count = r.get("layerCountAfter", 0)
        subview_count = r.get("subviewCountAfter", 0)
        
        actual_visible = True
        fail_reasons = []
        
        if not vis_text:
            actual_visible = False
            fail_reasons.append("Empty visibleGhostText")
        if not render_committed:
            actual_visible = False
            fail_reasons.append("Not renderCommitted")
        if not overlay_visible:
            actual_visible = False
            fail_reasons.append("Not overlayVisible")
        if commit_failed:
            actual_visible = False
            fail_reasons.append("InvisibleGhostGuard renderCommitFailed")
        if layer_count is None or layer_count <= 0:
            if subview_count is None or subview_count <= 0:
                actual_visible = False
                fail_reasons.append("layerCount/subviewCount <= 0")
            
        if not actual_visible:
            r["visibilityPass"] = False
            r["visibilityFailReasons"] = fail_reasons
        else:
            # Check visual integrity
            has_vi = r.get("hasVisualIntegrity", False)
            if not has_vi:
                actual_visible = False
                fail_reasons.append("BENCHMARK_VISUAL_OBSERVABILITY_GAP")
            else:
                if r.get("isTextClipped"):
                    actual_visible = False
                    fail_reasons.append("VISUAL_CLIP_FAIL")
                if r.get("isTextTruncated"):
                    actual_visible = False
                    fail_reasons.append("VISUAL_TRUNCATION_FAIL")
                if r.get("isOverlayBelowTypingLine"):
                    actual_visible = False
                    fail_reasons.append("VERTICAL_ALIGNMENT_FAIL")
                if not r.get("visualIntegrityPass"):
                    actual_visible = False
                    fail_reasons.append("VISUAL_INTEGRITY_FAIL")
            
            if not actual_visible:
                r["visibilityPass"] = False
                r["visibilityFailReasons"] = fail_reasons
            else:
                r["visibilityPass"] = True
                r["visibilityFailReasons"] = []
            
        q_label, q_reasons = evaluate_quality(r)
        r["qualityLabel"] = q_label
        r["qualityFailReasons"] = q_reasons

    actual_user_visible_count = sum(1 for r in continuous if r.get("visibilityPass"))
    diagnostic_ghost_visible_count = sum(1 for r in continuous if r.get("ghostVisible"))
    render_commit_fails = sum(1 for r in continuous if not r.get("visibilityPass") and r.get("ghostVisible"))
    
    invis_accept_fails = sum(1 for r in continuous if not r.get("visibilityPass") and r.get("acceptTapEnabled"))
    
    latencies = [r["latencyMs"] for r in continuous if r.get("latencyMs") is not None and r.get("visibilityPass")]
    p50 = statistics.median(latencies) if latencies else 0
    p90 = statistics.quantiles(latencies, n=10)[8] if len(latencies) >= 2 else (latencies[0] if latencies else 0)
    max_lat = max(latencies) if latencies else 0
    
    word_counts = [r["suggestionWordCount"] for r in continuous if r.get("visibilityPass")]
    median_words = statistics.median(word_counts) if word_counts else 0
    max_words = max(word_counts) if word_counts else 0
    
    c1 = sum(1 for w in word_counts if w == 1)
    c2 = sum(1 for w in word_counts if w == 2)
    c3_6 = sum(1 for w in word_counts if 3 <= w <= 6)
    
    pct1 = (c1 / len(word_counts) * 100) if word_counts else 0
    pct2 = (c2 / len(word_counts) * 100) if word_counts else 0
    pct3_6 = (c3_6 / len(word_counts) * 100) if word_counts else 0
    
    quality_pass_count = sum(1 for r in continuous if r.get("visibilityPass") and (r["qualityLabel"] == "likely_good" or r["qualityLabel"] == "too_short"))
    
    vis_pct = (actual_user_visible_count / total) * 100 if total > 0 else 0
    
    passed = True
    if vis_pct < 80:
        passed = False
    
    report_lines = []
    report_lines.append("# Continuous Visibility Benchmark Report")
    report_lines.append(f"**Verdict:** {'PASS' if passed else 'FAIL'}")
    report_lines.append(f"Note: Previous reports may have inflated visibility because they relied on internal diagnostics instead of strict UI rendering.")
    report_lines.append("")
    report_lines.append(f"- Total Checkpoints: {total}")
    report_lines.append(f"- Diagnostic ghostVisible count: {diagnostic_ghost_visible_count}")
    report_lines.append(f"- Actual user-visible count: {actual_user_visible_count} ({vis_pct:.1f}%)")
    report_lines.append(f"- Render commit failures: {render_commit_fails}")
    report_lines.append(f"- Invisible accept-ready failures: {invis_accept_fails}")
    report_lines.append(f"- Quality pass checkpoints: {quality_pass_count}")
    report_lines.append(f"- p50 Latency (actual visible only): {p50:.1f}ms")
    report_lines.append(f"- p90 Latency (actual visible only): {p90:.1f}ms")
    report_lines.append(f"- Max Latency (actual visible only): {max_lat:.1f}ms")
    report_lines.append(f"- Median suggestion word count: {median_words}")
    report_lines.append(f"- Max suggestion word count: {max_words}")
    report_lines.append(f"- % 1-word suggestions: {pct1:.1f}%")
    report_lines.append(f"- % 2-word suggestions: {pct2:.1f}%")
    report_lines.append(f"- % 3-6-word suggestions: {pct3_6:.1f}%")
    report_lines.append("")
    report_lines.append("## Checkpoint Details")
    report_lines.append("| Idx | Prefix | Raw Output | Final Sug | Vis Text | Disp Comp | Pend Cand | renderCommitted | actualUserVisible | latencyMs | pFstCandMs | pFstUseMs | pRdrComMs | Words | Qual | Fail Reasons |")
    report_lines.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    
    for r in continuous:
        idx = r.get("checkpointIndex")
        pref = r.get("typedPrefix", "")[-15:].replace("\n", " ")
        raw = str(r.get("rawOutput", ""))[:15].replace("\n", " ")
        fsug = str(r.get("finalSuggestion", ""))[:15].replace("\n", " ")
        vtxt = str(r.get("visibleGhostText", ""))[:15].replace("\n", " ")
        pend = str(r.get("pendingCandidate", ""))[:10].replace("\n", " ")
        disp = str(r.get("displayedCompletion", ""))[:10].replace("\n", " ")
        gv = r.get("ghostVisible")
        rc = r.get("renderCommitted", False)
        auv = r.get("visibilityPass", False)
        lat = f"{r.get('latencyMs', 0):.1f}"
        
        # We don't have all exact timings yet, so mapping what we have
        pFstCand = ""
        pFstUse = lat
        pRdrCom = f"{r.get('_observedPauseToVisibleMs', 0):.1f}"
        
        wds = r.get("suggestionWordCount", 0)
        ql = r.get("qualityLabel")
        frs = r.get("visibilityFailReasons", []) + r.get("qualityFailReasons", [])
        fr = ", ".join(frs)
        
        report_lines.append(f"| {idx} | `...{pref}` | `{raw}` | `{fsug}` | `{vtxt}` | `{disp}` | `{pend}` | {rc} | {auv} | {lat} | {pFstCand} | {pFstUse} | {pRdrCom} | {wds} | {ql} | {fr} |")
        
    report_content = "\n".join(report_lines)
    REPORT_PATH.write_text(report_content, encoding="utf-8")
    
if __name__ == "__main__":
    analyze()
