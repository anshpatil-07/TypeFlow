#!/usr/bin/env python3
import argparse
import atexit
import json
import os
import re
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
ARTIFACT_DIR = ROOT / "devtools" / "reports" / "benchmark_artifacts" / "prefix_consumption"
RESULTS_PATH = ARTIFACT_DIR / "results.json"
DIAGNOSTICS_LOG = os.environ.get("TYPEFLOW_DIAGNOSTICS_LOG", ROOT / "devtools" / "reports" / "benchmark_artifacts" / "prefix_consumption" / "typeflow_diagnostics.log")

SAFARI_BENCHMARK_WINDOW_ID = None

def run_command(command, timeout=None):
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
        '    click at {(item 1 of bnds) + 100, (item 2 of bnds) + 250}\n'
        '  end try\n'
        'end tell',
        timeout=3
    )
    time.sleep(0.2)

def safari_open_file(page_path):
    global SAFARI_BENCHMARK_WINDOW_ID
    url = page_path.resolve().as_uri()
    script = (
        'tell application "Safari"\n'
        '  activate\n'
        '  close every document\n'
        f'  make new document with properties {{URL:"{url}"}}\n'
        '  delay 0.5\n'
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
    stdout_val = result.stdout.strip()
    return stdout_val

def focus_and_clear():
    activate_safari()
    safari_eval_javascript("document.querySelector('#editor').focus();")
    time.sleep(0.05)
    script = (
        'tell application "System Events"\n'
        '  tell process "Safari"\n'
        '    keystroke "a" using command down\n'
        '    delay 0.05\n'
        '    key code 51\n'
        '  end tell\n'
        'end tell'
    )
    osascript(script, timeout=5)
    time.sleep(0.1)

def keystroke_text(text):
    delay_ms = 45
    script_path = Path(__file__).parent / "type_text"
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

def wait_for_ghost(timeout=2.5):
    start = time.time()
    log_file = Path(DIAGNOSTICS_LOG)
    last_text = None
    stable_since = None
    
    while time.time() - start < timeout:
        if log_file.exists():
            try:
                tail = subprocess.check_output(["tail", "-n", "100", str(log_file)], text=True, errors="replace")
                current_text = None
                for line in reversed(tail.splitlines()):
                    if line.startswith("{"):
                        rec = json.loads(line)
                        epoch = float(rec.get("epochSeconds") or 0)
                        if epoch >= start - 5 and rec.get("ghostVisible") == True:
                            txt = rec.get("visibleGhostText") or rec.get("finalSuggestion")
                            if txt:
                                current_text = txt
                                break
                if current_text:
                    if current_text == last_text:
                        if time.time() - stable_since >= 0.4:
                            return current_text, epoch
                    else:
                        last_text = current_text
                        stable_since = time.time()
            except Exception:
                pass
        time.sleep(0.1)
    if last_text:
        return last_text, time.time()
    return None, None

def get_prefix_diagnostics(since_epoch):
    log_file = Path(DIAGNOSTICS_LOG)
    if not log_file.exists():
        return []
    records = []
    try:
        content = log_file.read_text(errors="replace")
        for line in content.splitlines():
            if "[PrefixConsumptionDiagnostic]" in line:
                try:
                    json_str = line.split("[PrefixConsumptionDiagnostic] ")[1]
                    record = json.loads(json_str)
                    epoch = float(record.get("epochSeconds") or 0)
                    if epoch >= since_epoch:
                        records.append(record)
                except Exception:
                    pass
    except Exception:
        pass
    return records

def test_prefix_consumption_cycle(case_name, prefix_to_type, expected_sug_hint=None):
    focus_and_clear()
    time.sleep(0.2)
    # Type initial prefix
    keystroke_text(prefix_to_type)
    
    # Wait for ghost suggestion to appear and stabilize
    txt, start_epoch = wait_for_ghost()
    if not txt:
        print(f"[{case_name}] FAILED: No ghost suggestion appeared.")
        return False, []
    
    print(f"[{case_name}] Ghost suggestion appeared: '{txt}'")
    
    # We will type it character by character, and measure
    latencies = []
    since_epoch = time.time()
    
    # Track diagnostic records
    for i, char in enumerate(txt):
        t0 = time.perf_counter()
        keystroke_text(char)
        
        # Poll for PrefixConsumptionDiagnostic
        diag_rec = None
        deadline = time.time() + 1.0
        while time.time() < deadline:
            diags = get_prefix_diagnostics(since_epoch)
            if diags:
                diag_rec = diags[-1]
                break
            time.sleep(0.01)
        
        t1 = time.perf_counter()
        if not diag_rec:
            print(f"[{case_name}] FAILED: No PrefixConsumptionDiagnostic record found for char '{char}' (idx {i}).")
            return False, []
        
        lat = (t1 - t0) * 1000.0
        latencies.append(lat)
        
        # Verify prefixMatched
        if not diag_rec.get("prefixMatched"):
            print(f"[{case_name}] FAILED: prefixMatched is False for char '{char}' (idx {i}). Record: {diag_rec}")
            return False, []
        
        # Verify no LLM request triggered (should be true for all but the last character if consumed to empty)
        is_last = (i == len(txt) - 1)
        if not is_last:
            if diag_rec.get("consumedToEmpty") == True:
                print(f"[{case_name}] FAILED: ghost consumed to empty before the last character.")
                return False, []
        else:
            if not diag_rec.get("consumedToEmpty") == True:
                print(f"[{case_name}] FAILED: ghost not consumed to empty on last character.")
                return False, []
        
        since_epoch = time.time()
        
    print(f"[{case_name}] PASSED: prefix consumption succeeded. Avg latency = {sum(latencies)/len(latencies):.1f}ms")
    return True, latencies

def main():
    parser = argparse.ArgumentParser()
    args = parser.parse_args()
    
    # Enable testing mode for context extraction stability
    os.environ["TYPEFLOW_TESTING_MODE"] = "1"
    
    ARTIFACT_DIR.mkdir(parents=True, exist_ok=True)
    
    # Create test page locally with static context pre-loaded on a single line
    page_path = ARTIFACT_DIR / "prefix_benchmark.html"
    page_path.write_text(
        """<html>
        <body>
        <div id="context" style="color:#666;font-family:monospace;padding:10px;">public class Helper { public void doSomeMath() {} }</div>
        <textarea id="editor" style="width:800px;height:600px;"></textarea>
        </body>
        </html>""",
        encoding="utf-8"
    )
    
    activate_safari()
    safari_open_file(page_path)
    time.sleep(1.0)
    
    results = {}
    
    # Case 1: after-space prose suggestion
    prose_passes = 0
    prose_lats = []
    for cycle in range(5):
        passed, lats = test_prefix_consumption_cycle(f"prose_cycle_{cycle}", "The quick brown ")
        if passed:
            prose_passes += 1
            prose_lats.extend(lats)
        time.sleep(0.3)
        
    # Case 2: mid-word suggestion
    midword_passes = 0
    midword_lats = []
    for cycle in range(5):
        passed, lats = test_prefix_consumption_cycle(f"midword_cycle_{cycle}", "public clas")
        if passed:
            midword_passes += 1
            midword_lats.extend(lats)
        time.sleep(0.3)
        
    # Case 3: page-context suggestion
    pagecontext_passes = 0
    pagecontext_lats = []
    for cycle in range(5):
        passed, lats = test_prefix_consumption_cycle(f"pagecontext_cycle_{cycle}", "public class Helper { public void d")
        if passed:
            pagecontext_passes += 1
            pagecontext_lats.extend(lats)
        time.sleep(0.3)
        
    # Case 4: punctuation/space-containing suggestion
    punc_passes = 0
    punc_lats = []
    for cycle in range(5):
        passed, lats = test_prefix_consumption_cycle(f"punctuation_cycle_{cycle}", "SELECT * FROM users WHERE ")
        if passed:
            punc_passes += 1
            punc_lats.extend(lats)
        time.sleep(0.3)
        
    # Case 5: full-consumption then next-generation
    full_passes = 0
    for cycle in range(3):
        focus_and_clear()
        keystroke_text("The quick brown ")
        txt, start_epoch = wait_for_ghost()
        if not txt:
            continue
        # Type the suggestion
        keystroke_text(txt)
        time.sleep(0.1)
        # Verify next suggestion is scheduled and rendered after the 25ms idle
        next_txt, _ = wait_for_ghost(timeout=2.0)
        if next_txt:
            full_passes += 1
        time.sleep(0.3)
        
    # Case 6: divergence negative case
    diverge_passes = 0
    for cycle in range(3):
        focus_and_clear()
        keystroke_text("The quick brown ")
        txt, start_epoch = wait_for_ghost()
        if not txt:
            continue
        # Type divergent character
        since_epoch = time.time()
        keystroke_text("x")
        
        # Poll for PrefixConsumptionDiagnostic
        diag_rec = None
        deadline = time.time() + 1.0
        while time.time() < deadline:
            diags = get_prefix_diagnostics(since_epoch)
            if diags:
                diag_rec = diags[-1]
                break
            time.sleep(0.01)
            
        if diag_rec and diag_rec.get("divergenceDetected") == True:
            diverge_passes += 1
        time.sleep(0.3)
        
    # Calculate stats
    all_lats = prose_lats + midword_lats + pagecontext_lats + punc_lats
    all_lats.sort()
    
    p50 = all_lats[int(len(all_lats)*0.5)] if all_lats else 0
    p90 = all_lats[int(len(all_lats)*0.9)] if all_lats else 0
    
    results = {
        "prosePassRate": prose_passes / 5.0,
        "midwordPassRate": midword_passes / 5.0,
        "pagecontextPassRate": pagecontext_passes / 5.0,
        "punctuationPassRate": punc_passes / 5.0,
        "fullConsumptionPassRate": full_passes / 3.0,
        "divergencePassRate": diverge_passes / 3.0,
        "latency_p50": p50,
        "latency_p90": p90,
    }
    
    RESULTS_PATH.write_text(json.dumps(results, indent=2))
    print(f"BENCHMARK_RESULTS: {json.dumps(results)}")
    
    cleanup_safari_window()

if __name__ == "__main__":
    main()
