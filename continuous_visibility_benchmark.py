#!/usr/bin/env python3
"""
Continuous visibility product benchmark runner for TypeFlow.
Tests ghost visibility across continuous typing pauses.
"""

import argparse
import atexit
import json
import os
import re
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
ARTIFACT_DIR = ROOT / "benchmark_artifacts" / "continuous_visibility"
PAGES_DIR = ARTIFACT_DIR / "pages"
SCREENSHOTS_DIR = ARTIFACT_DIR / "screenshots"
RESULTS_PATH = ARTIFACT_DIR / "results.jsonl"
FIXTURE_PATH = ROOT / "tests" / "fixtures" / "continuous_visibility_paragraph.json"
DIAGNOSTICS_LOG = os.environ.get("TYPEFLOW_DIAGNOSTICS_LOG", ROOT / "benchmark_artifacts" / "typeflow_diagnostics.log")

SAFARI_BENCHMARK_WINDOW_ID = None

def run_command(command, timeout=None, check=False):
    import tempfile
    with tempfile.TemporaryFile(mode="w+") as out, tempfile.TemporaryFile(mode="w+") as err:
        try:
            with subprocess.Popen(command, stdout=out, stderr=err, text=True) as p:
                p.wait(timeout=timeout)
        except subprocess.TimeoutExpired as exc:
            p.kill()
            p.wait()
            raise exc
        out.seek(0)
        err.seek(0)
        stdout_text = out.read()
        stderr_text = err.read()
    if check and p.returncode != 0:
        raise subprocess.CalledProcessError(p.returncode, command, stdout_text, stderr_text)
    return subprocess.CompletedProcess(command, p.returncode, stdout_text, stderr_text)

def osascript(script, timeout=None):
    return run_command(["osascript", "-e", script], timeout=timeout)

def activate_safari():
    osascript('tell application "Safari" to activate', timeout=5)
    osascript('tell application "System Events" to set frontmost of process "Safari" to true', timeout=5)
    osascript(
        'tell application "System Events" to tell process "Safari"\n'
        '  try\n'
        '    click menu item "Hide Sidebar" of menu "View" of menu bar 1\n'
        '  end try\n'
        'end tell',
        timeout=3
    )
    time.sleep(0.15)
    osascript(
        'tell application "Safari"\n'
        '  try\n'
        '    set bnds to bounds of front window\n'
        '  on error\n'
        '    return\n'
        '  end try\n'
        'end tell\n'
        'tell application "System Events" to tell process "Safari"\n'
        '  try\n'
        '    click at {(item 1 of bnds) + ((item 3 of bnds) - (item 1 of bnds)) / 2, (item 2 of bnds) + ((item 4 of bnds) - (item 2 of bnds)) / 2}\n'
        '  end try\n'
        'end tell',
        timeout=3
    )
    time.sleep(0.15)

def safari_open_file(page_path):
    global SAFARI_BENCHMARK_WINDOW_ID
    url = page_path.resolve().as_uri()
    script = (
        'tell application "Safari"\n'
        '  activate\n'
        '  close every document\n'
        f'  make new document with properties {{URL:"{url}"}}\n'
        '  delay 0.2\n'
        '  return id of front window\n'
        'end tell'
    )
    result = osascript(script, timeout=10)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "Safari open failed")
    if not SAFARI_BENCHMARK_WINDOW_ID:
        SAFARI_BENCHMARK_WINDOW_ID = result.stdout.strip()

def cleanup_safari_window():
    global SAFARI_BENCHMARK_WINDOW_ID
    if not SAFARI_BENCHMARK_WINDOW_ID:
        return
    osascript(
        'tell application "Safari"\n'
        f'  if exists (first window whose id is {SAFARI_BENCHMARK_WINDOW_ID}) then close (first window whose id is {SAFARI_BENCHMARK_WINDOW_ID})\n'
        "end tell",
        timeout=5
    )
    SAFARI_BENCHMARK_WINDOW_ID = None

def safari_eval_javascript(source):
    escaped = source.replace("\\", "\\\\").replace('"', '\\"')
    script = (
        'tell application "Safari"\n'
        '  tell current tab of front window\n'
        f'    do JavaScript "{escaped}"\n'
        "  end tell\n"
        "end tell"
    )
    result = osascript(script, timeout=10)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "Safari JavaScript failed")
    return result.stdout.strip()

def wait_for_page_ready(timeout_seconds=5.0):
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        try:
            state = safari_eval_javascript("document.readyState")
            if state in {"interactive", "complete"}:
                return
        except Exception:
            pass
        time.sleep(0.1)
    raise RuntimeError("Safari page did not become JS-ready")

def write_page():
    PAGES_DIR.mkdir(parents=True, exist_ok=True)
    path = PAGES_DIR / "continuous_benchmark.html"
    path.write_text(
        """<!doctype html>
<html>
<head><meta charset="utf-8"><title>TypeFlow Continuous Visibility Benchmark</title>
<style>
body { margin: 0; background: #fff; }
#editor { width: 800px; height: 600px; margin: 20px; font-size: 20px; font-family: monospace; white-space: pre-wrap; outline: none; border: 1px solid #ccc; padding: 10px; }
</style>
</head>
<body>
  <div id="editor" contenteditable="true" spellcheck="false" role="textbox"></div>
</body>
</html>
""", encoding="utf-8"
    )
    return path

def focus_and_clear():
    js = (
        "{"
        "const el=document.querySelector('#editor');"
        "el.focus(); el.innerText='';"
        "const r = document.createRange();"
        "r.selectNodeContents(el);"
        "r.collapse(false);"
        "const s = window.getSelection();"
        "s.removeAllRanges();"
        "s.addRange(r);"
        "}"
        "'ok';"
    )
    safari_eval_javascript(js)

def assert_editor_focused():
    js = (
        "(() => {"
        "const el=document.querySelector('#editor');"
        "return JSON.stringify(!!el && (el === document.activeElement || el.contains(document.activeElement)));"
        "})();"
    )
    focused = json.loads(safari_eval_javascript(js))
    if not focused:
        raise RuntimeError("SAFARI_FOCUS_FAIL: benchmark editor is not focused")

def read_editor_text():
    js = "JSON.stringify(document.querySelector('#editor').innerText)"
    raw = safari_eval_javascript(js)
    return json.loads(raw)

def keystroke_text(text):
    delay_ms = 45
    time.sleep(0.1)
    script_path = ROOT / "type_text"
    if script_path.exists():
        subprocess.run([str(script_path), text, str(delay_ms)], check=True)
    else:
        for character in text:
            if character == "\n":
                script = 'tell application "System Events" to tell process "Safari" to key code 36'
            elif character == "\t":
                script = 'tell application "System Events" to tell process "Safari" to key code 48'
            else:
                escaped = character.replace("\\", "\\\\").replace('"', '\\"')
                script = f'tell application "System Events" to tell process "Safari" to keystroke "{escaped}"'
            osascript(script, timeout=5)
            time.sleep(delay_ms / 1000.0)
    return time.perf_counter()

def find_latest_diagnostic(log_path, since_epoch, prefix):
    try:
        log_file = Path(log_path)
        if not log_file.exists():
            return {}
        tail_output = subprocess.check_output(["tail", "-n", "400", str(log_file)], text=True, errors="replace")
        best_record = {}
        
        # Persist these rendering states because they might arrive slightly before or after the JSON tick
        layer_count = None
        subview_count = None
        commit_failed = False
        overlay_visible = False
        render_committed = False
        
        has_visual_integrity = False
        visual_integrity_pass = False
        is_text_clipped = False
        is_text_truncated = False
        is_overlay_below_typing_line = False
        
        for line in tail_output.splitlines():
            if line.startswith("{"):
                try:
                    record = json.loads(line)
                    epoch = float(record.get("epochSeconds") or record.get("timestampEpoch") or record.get("time") or 0)
                    if epoch < since_epoch:
                        continue
                    active_line = str(record.get("activeLine") or "")
                    if active_line and not prefix.endswith(active_line) and not active_line.endswith(prefix[-min(len(prefix), len(active_line)):]):
                        continue
                    best_record = record
                    # Do not reset layout variables here, since they may have arrived just before this line
                except Exception:
                    pass
            else:
                if "[OverlayRender]" in line:
                    m1 = re.search(r"layerCountAfter=(\d+)", line)
                    if m1: layer_count = int(m1.group(1))
                    m2 = re.search(r"subviewCountAfter=(\d+)", line)
                    if m2: subview_count = int(m2.group(1))
                    overlay_visible = True
                    render_committed = True
                if "[RenderPipeline]" in line:
                    m = re.search(r"layerCountAfter=(\d+)", line)
                    if m: layer_count = int(m.group(1))
                    m_sub = re.search(r"subviewCountAfter=(\d+)", line)
                    if m_sub: subview_count = int(m_sub.group(1))
                if "[InvisibleGhostGuard] renderCommitFailed" in line:
                    commit_failed = True
                    render_committed = False
                if "[VisualIntegrity]" in line:
                    try:
                        json_str = line.split("[VisualIntegrity] ")[1]
                        v_data = json.loads(json_str)
                        has_visual_integrity = True
                        visual_integrity_pass = v_data.get("visualIntegrityPass", False)
                        is_text_clipped = v_data.get("isTextClipped", False)
                        is_text_truncated = v_data.get("isTextTruncated", False)
                        is_overlay_below_typing_line = v_data.get("isOverlayBelowTypingLine", False)
                    except Exception:
                        pass

        if best_record:
            best_record["layerCountAfter"] = layer_count
            best_record["subviewCountAfter"] = subview_count
            best_record["commitFailed"] = commit_failed
            best_record["overlayVisible"] = overlay_visible
            best_record["renderCommitted"] = render_committed
            
            best_record["hasVisualIntegrity"] = has_visual_integrity
            best_record["visualIntegrityPass"] = visual_integrity_pass
            best_record["isTextClipped"] = is_text_clipped
            best_record["isTextTruncated"] = is_text_truncated
            best_record["isOverlayBelowTypingLine"] = is_overlay_below_typing_line
        return best_record
    except Exception:
        pass
    return {}

def observe_visibility(start_epoch, pause_time, prefix, timeout_ms=300):
    deadline = pause_time + (timeout_ms / 1000.0)
    first_usable_ms = None
    best = {}
    while time.perf_counter() <= deadline:
        latest = find_latest_diagnostic(DIAGNOSTICS_LOG, start_epoch, prefix)
        visible = bool(latest.get("ghostVisible") or latest.get("overlayVisible"))
        visible_text = str(latest.get("visibleGhostText") or "").strip()
        if visible and visible_text:
            if first_usable_ms is None:
                first_usable_ms = (time.perf_counter() - pause_time) * 1000.0
            best = latest
        time.sleep(0.015)
    
    if first_usable_ms is None:
        best = find_latest_diagnostic(DIAGNOSTICS_LOG, start_epoch, prefix)
        first_usable_ms = (time.perf_counter() - pause_time) * 1000.0
    
    best["_observedPauseToVisibleMs"] = round(first_usable_ms, 3)
    return best

def run():
    atexit.register(cleanup_safari_window)
    ARTIFACT_DIR.mkdir(parents=True, exist_ok=True)
    SCREENSHOTS_DIR.mkdir(parents=True, exist_ok=True)
    
    with open(FIXTURE_PATH, "r") as f:
        fixture = json.load(f)
        
    paragraph = fixture["paragraph"]
    words = paragraph.split(" ")
    
    page_path = write_page()
    safari_open_file(page_path)
    wait_for_page_ready()
    activate_safari()
    time.sleep(0.1)
    
    # Press Esc to clear address bar focus
    osascript('tell application "System Events" to tell process "Safari" to key code 53', timeout=5)
    time.sleep(0.1)
    
    focus_and_clear()
    time.sleep(0.15)
    assert_editor_focused()
    
    results = []
    typed_so_far = ""
    
    # Part 1: Continuous typing
    for i in range(0, len(words), 2):
        chunk = " ".join(words[i:i+2])
        if i + 2 < len(words):
            chunk += " "
            
        start_epoch = time.time()
        pause_time = keystroke_text(chunk)
        typed_so_far += chunk
        
        # Verify typed text
        editor_text = read_editor_text()
        if not editor_text.strip().endswith(chunk.strip()):
            pass # We could raise, but let's just log it if we have to
            
        diag = observe_visibility(start_epoch, pause_time, typed_so_far, timeout_ms=300)
        
        expected_next = words[i+2:i+6] if i+2 < len(words) else []
        
        visible_text = str(diag.get("visibleGhostText") or "").strip()
        suggestion_words = len(visible_text.split()) if visible_text else 0
        
        res = {
            "checkpointIndex": i // 2,
            "scenario": "continuous",
            "typedPrefix": typed_so_far,
            "expectedNextWordsForContextOnly": expected_next,
            "ghostVisible": bool(diag.get("ghostVisible")),
            "visibleGhostText": visible_text,
            "pendingCandidate": str(diag.get("pendingCandidate") or ""),
            "displayedCompletion": str(diag.get("displayedCompletion") or ""),
            "renderCommitted": bool(diag.get("renderCommitted")),
            "overlayVisible": bool(diag.get("overlayVisible")),
            "layerCountAfter": diag.get("layerCountAfter"),
            "subviewCountAfter": diag.get("subviewCountAfter"),
            "commitFailed": bool(diag.get("commitFailed")),
            "rawOutput": str(diag.get("rawOutput") or ""),
            "finalSuggestion": str(diag.get("finalSuggestion") or ""),
            "acceptTapEnabled": bool(diag.get("acceptTapEnabled")),
            "latencyMs": diag.get("totalPauseToVisibleMs") or diag.get("_observedPauseToVisibleMs"),
            "suggestionWordCount": suggestion_words,
            "requestID": str(diag.get("requestID") or ""),
            "activeLine": str(diag.get("activeLine") or ""),
            "hasVisualIntegrity": bool(diag.get("hasVisualIntegrity")),
            "visualIntegrityPass": bool(diag.get("visualIntegrityPass")),
            "isTextClipped": bool(diag.get("isTextClipped")),
            "isTextTruncated": bool(diag.get("isTextTruncated")),
            "isOverlayBelowTypingLine": bool(diag.get("isOverlayBelowTypingLine")),
            "isOverlayFrameTooSmall": bool(diag.get("isOverlayFrameTooSmall"))
        }
        results.append(res)
        
    # Part 2: Divergence
    div_fix = fixture["divergeScenario"]
    div_prefix = div_fix["prefix"]
    div_text = div_fix["divergeText"]
    
    focus_and_clear()
    time.sleep(0.15)
    assert_editor_focused()
    
    start_epoch = time.time()
    pause_time = keystroke_text(div_prefix)
    
    # wait for ghost
    diag = observe_visibility(start_epoch, pause_time, div_prefix, timeout_ms=300)
    
    # type divergence
    start_epoch2 = time.time()
    pause_time2 = keystroke_text(div_text)
    
    # check immediately
    diag2 = observe_visibility(start_epoch2, pause_time2, div_prefix + div_text, timeout_ms=100)
    
    res = {
        "checkpointIndex": len(words),
        "scenario": "divergence",
        "typedPrefix": div_prefix + div_text,
        "ghostVisible": bool(diag2.get("ghostVisible") or diag2.get("overlayVisible")),
        "visibleGhostText": str(diag2.get("visibleGhostText") or "").strip(),
        "displayedCompletion": str(diag2.get("displayedCompletion") or ""),
        "acceptTapEnabled": bool(diag2.get("acceptTapEnabled")),
        "staleAcceptReady": bool(diag2.get("acceptTapEnabled")) and (str(diag2.get("visibleGhostText") or "") == str(diag.get("visibleGhostText") or "")),
        "latencyMs": diag2.get("_observedPauseToVisibleMs")
    }
    results.append(res)
    
    with open(RESULTS_PATH, "w") as f:
        for r in results:
            f.write(json.dumps(r) + "\n")

if __name__ == "__main__":
    run()
