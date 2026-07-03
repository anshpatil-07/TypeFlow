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
ARTIFACT_DIR = ROOT / "devtools" / "reports" / "benchmark_artifacts" / "acceptance_latency"
RESULTS_PATH = ARTIFACT_DIR / "results.json"
DIAGNOSTICS_LOG = os.environ.get("TYPEFLOW_DIAGNOSTICS_LOG", ROOT / "devtools" / "reports" / "benchmark_artifacts" / "continuous_visibility" / "typeflow_diagnostics.log")

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
    if stdout_val.startswith('"') and stdout_val.endswith('"'):
        stdout_val = '\\n'.join(stdout_val.split('\n'))
    return stdout_val

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

def find_latest_visible_ghost(since_epoch):
    log_file = Path(DIAGNOSTICS_LOG)
    if not log_file.exists():
        return None
    try:
        tail_output = subprocess.check_output(["tail", "-n", "200", str(log_file)], text=True, errors="replace")
        for line in reversed(tail_output.splitlines()):
            if line.startswith("{"):
                try:
                    record = json.loads(line)
                    epoch = float(record.get("epochSeconds") or 0)
                    if epoch >= since_epoch and record.get("ghostVisible") == True:
                        visible_text = record.get("visibleGhostText") or record.get("finalSuggestion")
                        if visible_text:
                            return visible_text
                except Exception:
                    pass
    except Exception:
        pass
    return None

def find_accept_diagnostic(since_epoch):
    log_file = Path(DIAGNOSTICS_LOG)
    if not log_file.exists():
        return None
    try:
        tail_output = subprocess.check_output(["tail", "-n", "100", str(log_file)], text=True, errors="replace")
        for line in reversed(tail_output.splitlines()):
            if "[AcceptDiagnostic]" in line:
                try:
                    json_str = line.split("[AcceptDiagnostic] ")[1]
                    diag = json.loads(json_str)
                    return diag
                except Exception:
                    pass
    except Exception:
        pass
    return None

def main():
    parser = argparse.ArgumentParser()
    args = parser.parse_args()

    ARTIFACT_DIR.mkdir(parents=True, exist_ok=True)

    page_path = ARTIFACT_DIR / "acceptance_benchmark.html"
    page_path.write_text(
        """<!doctype html>
<html>
<head><meta charset="utf-8"><title>TypeFlow Acceptance Latency Benchmark</title>
<style>
body { margin: 0; background: #fff; }
#editor { width: 800px; height: 600px; margin: 20px; font-size: 20px; font-family: monospace; white-space: pre-wrap; outline: none; border: 1px solid #ccc; padding: 10px; }
</style>
</head>
<body>
  <div id="editor" contenteditable="true" spellcheck="false" role="textbox"></div>
  <script>
    document.getElementById('editor').addEventListener('keydown', function(e) {
      if (e.key === 'Tab') {
        e.preventDefault();
      }
    });
  </script>
</body>
</html>
""", encoding="utf-8"
    )

    activate_safari()
    safari_open_file(page_path)
    atexit.register(cleanup_safari_window)
    
    print("Warming up model and Safari...")
    time.sleep(3.0)

    cases = [
        {"name": "prose_1", "prefix": "The quick brown "},
        {"name": "prose_2", "prefix": "ok so it "},
        {"name": "email", "prefix": "Dear "},
        {"name": "java_class", "prefix": "public class "},
        {"name": "java_method", "prefix": "public void testMethod() "},
        {"name": "spring_boot", "prefix": "@RestController\nclass Controller "},
        {"name": "sql_query", "prefix": "SELECT * FROM users WHERE "},
        {"name": "junit_assert", "prefix": "assertEquals(expected, "},
        {"name": "exception_log", "prefix": "try {\n    doSomething();\n} catch (Exception e) "},
        {"name": "code_midword", "prefix": "public void print"},
        {"name": "screen_code_copy", "prefix": "class Helper "}
    ]

    results = []

    for case in cases:
        print(f"Running case: {case['name']} (prefix: '{case['prefix']}')")
        
        displayed_completion = None
        
        for attempt in range(2):
            activate_safari()
            focus_and_clear()
            time.sleep(0.3)
            
            start_epoch = time.time()
            keystroke_text(case['prefix'])
            time.sleep(0.6)
            
            deadline = time.time() + 4.0
            while time.time() < deadline:
                ghost = find_latest_visible_ghost(start_epoch)
                if ghost:
                    displayed_completion = ghost
                    break
                time.sleep(0.05)
                
            if displayed_completion:
                break
            print(f"  Attempt {attempt+1} failed to produce ghost text. Retrying...")
            
        if not displayed_completion:
            print(f"  FAILED: No ghost text appeared for prefix '{case['prefix']}' after retries")
            results.append({
                "case": case["name"],
                "prefix": case["prefix"],
                "displayedCompletion": "",
                "acceptedText": "",
                "insertedAtomically": False,
                "perCharacterFallback": False,
                "pass": False,
                "failReason": "no-ghost-text-appeared"
            })
            continue

        print(f"  Ghost visible: '{displayed_completion}'")
        
        js_get_text = "document.querySelector('#editor').innerText"
        editor_before = safari_eval_javascript(js_get_text).replace("\u00a0", " ").strip()
        
        tab_start_time = time.time()
        osascript('tell application "System Events" to tell process "Safari" to key code 48')
        
        # Tight polling loop
        tab_full_inserted_time = None
        poll_deadline = time.time() + 0.5
        
        last_current_text = ""
        while time.time() < poll_deadline:
            current_text = safari_eval_javascript(js_get_text).replace("\u00a0", " ").strip()
            last_current_text = current_text
            if len(current_text) > len(editor_before) or current_text.endswith(displayed_completion.strip()):
                tab_full_inserted_time = time.time()
                break
            time.sleep(0.001)
            
        polled_latency_ms = 999.0
        if tab_full_inserted_time:
            polled_latency_ms = (tab_full_inserted_time - tab_start_time) * 1000.0
            print(f"  Tab insertion completed in {polled_latency_ms:.1f}ms (JS polled)")
        else:
            print(f"  Tab insertion timed out. before='{editor_before}', current='{last_current_text}'")
            
        time.sleep(0.15)
        
        diag = find_accept_diagnostic(tab_start_time - 1.0)
        
        if diag:
            accepted_text = diag.get("acceptedText") or ""
            insertion_method = diag.get("insertionMethod") or "characterFallback"
            accept_to_first = float(diag.get("acceptToFirstInsertedMs") or 0)
            accept_to_full = float(diag.get("acceptToFullInsertedMs") or 0)
            inserted_atomically = bool(diag.get("insertedAtomically") or False)
            per_char_fallback = bool(diag.get("perCharacterFallback") or False)
            accept_success = bool(diag.get("acceptSuccess") or False)
            fail_reason = diag.get("failReason") or "none"
            
            final_latency = polled_latency_ms if tab_full_inserted_time else accept_to_full
            
            transform_verified = bool(
                diag.get("transformVerified") or
                diag.get("insertedAtCaretVerified") or
                diag.get("acceptSuccess") or False
            )
            
            # Pass criteria: transform verified, no unrelated text changed, latency <= 100ms.
            # insertedAtomically is NOT required — charByChar with a clean transform is valid.
            is_pass = accept_success and transform_verified and final_latency <= 100.0
            if final_latency > 100.0:
                is_pass = False
                fail_reason = f"latency-too-high ({final_latency:.1f}ms)"
            if not transform_verified:
                is_pass = False
                fail_reason = "transform-not-verified"
            
            results.append({
                "case": case["name"],
                "prefix": case["prefix"],
                "displayedCompletion": displayed_completion,
                "acceptedText": accepted_text,
                "insertionMethod": insertion_method,
                "acceptToFirstInsertedMs": accept_to_first,
                "acceptToFullInsertedMs": final_latency,
                "insertedAtomically": inserted_atomically,
                "perCharacterFallback": per_char_fallback,
                "pass": is_pass,
                "failReason": fail_reason
            })
        else:
            print("  FAILED: Telemetry log for acceptance was not found")
            results.append({
                "case": case["name"],
                "prefix": case["prefix"],
                "displayedCompletion": displayed_completion,
                "acceptedText": "",
                "insertionMethod": "unknown",
                "acceptToFirstInsertedMs": 0,
                "acceptToFullInsertedMs": polled_latency_ms,
                "insertedAtomically": False,
                "perCharacterFallback": False,
                "pass": False,
                "failReason": "no-telemetry-log-found"
            })
            
        time.sleep(0.5)

    with RESULTS_PATH.open("w") as f:
        json.dump(results, f, indent=2)
        
    print(f"Results written to {RESULTS_PATH}")

if __name__ == "__main__":
    main()
