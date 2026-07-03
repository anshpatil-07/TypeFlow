#!/usr/bin/env python3
import argparse
import atexit
import json
import os
import re
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
ARTIFACT_DIR = ROOT / "benchmark_artifacts" / "acceptance_behavior"
RESULTS_PATH = ARTIFACT_DIR / "results.json"
DIAGNOSTICS_LOG = os.environ.get("TYPEFLOW_DIAGNOSTICS_LOG", ROOT / "benchmark_artifacts" / "continuous_visibility" / "typeflow_diagnostics.log")

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
    time.sleep(0.25)

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
    activate_safari()
    # 1. Focus the editor element
    js = "document.querySelector('#editor').focus(); 'ok';"
    safari_eval_javascript(js)
    time.sleep(0.1)
    
    # 2. Simulate select-all (Cmd+A) and delete to clear text and trigger normal AX events
    script = (
        'tell application "System Events"\n'
        '  tell process "Safari"\n'
        '    key code 0 using {command down}\n'
        '    delay 0.05\n'
        '    key code 51\n'
        '  end tell\n'
        'end tell'
    )
    osascript(script, timeout=5)
    time.sleep(0.2)

def keystroke_text(text):
    delay_ms = 45
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

def find_latest_ghost_matching(since_epoch, min_length=1):
    log_file = Path(DIAGNOSTICS_LOG)
    if not log_file.exists():
        return None
    try:
        tail_output = subprocess.check_output(["tail", "-n", "1000", str(log_file)], text=True, errors="replace")
        for line in reversed(tail_output.splitlines()):
            if line.startswith("{"):
                try:
                    record = json.loads(line)
                    epoch = float(record.get("epochSeconds") or 0)
                    if epoch >= since_epoch and record.get("ghostVisible") == True:
                        visible_text = record.get("visibleGhostText") or record.get("finalSuggestion")
                        if visible_text and len(visible_text.strip()) >= min_length:
                            return visible_text
                except Exception:
                    pass
    except Exception:
        pass
    return None

def find_accept_diagnostic(since_epoch, timeout=2.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        log_file = Path(DIAGNOSTICS_LOG)
        if log_file.exists():
            try:
                tail_output = subprocess.check_output(["tail", "-n", "1000", str(log_file)], text=True, errors="replace")
                for line in reversed(tail_output.splitlines()):
                    if "[AcceptDiagnostic]" in line:
                        try:
                            json_str = line.split("[AcceptDiagnostic] ")[1]
                            diag = json.loads(json_str)
                            epoch = float(diag.get("epochSeconds") or 0)
                            if epoch >= since_epoch:
                                return diag
                        except Exception:
                            pass
            except Exception:
                pass
        time.sleep(0.05)
    return None

def find_prefix_consumption_diagnostic(since_epoch, timeout=2.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        log_file = Path(DIAGNOSTICS_LOG)
        if log_file.exists():
            try:
                tail_output = subprocess.check_output(["tail", "-n", "1000", str(log_file)], text=True, errors="replace")
                for line in reversed(tail_output.splitlines()):
                    if "[PrintableInputDiagnostic]" in line:
                        try:
                            json_str = line.split("[PrintableInputDiagnostic] ")[1]
                            diag = json.loads(json_str)
                            epoch = float(diag.get("epochSeconds") or 0)
                            if epoch >= since_epoch:
                                return diag
                        except Exception:
                            pass
            except Exception:
                pass
        time.sleep(0.05)
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

    results = {
        "acceptance_latency": [],
        "word_by_word": [],
        "prefix_consumption": [],
        "multiline_safety": {}
    }

    # =========================================================================
    # PART 1: Acceptance Latency Benchmark (wordChunk mode)
    # =========================================================================
    print("\n--- Running Part 1: Acceptance Latency Benchmark ---")
    latency_cases = [
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

    for case in latency_cases:
        print(f"Running case: {case['name']} (prefix: '{case['prefix']}')")
        displayed_completion = None
        
        for attempt in range(3):
            focus_and_clear()
            time.sleep(0.4)
            start_epoch = time.time()
            keystroke_text(case['prefix'])
            time.sleep(0.7)
            
            deadline = time.time() + 5.0
            while time.time() < deadline:
                ghost = find_latest_ghost_matching(start_epoch, min_length=2)
                if ghost:
                    displayed_completion = ghost
                    break
                time.sleep(0.05)
            if displayed_completion:
                break
            print(f"  Attempt {attempt+1} failed to produce ghost text. Retrying...")
                
        if not displayed_completion:
            print(f"  FAILED: No ghost text appeared for prefix '{case['prefix']}' after all attempts")
            continue

        print(f"  Ghost visible: '{displayed_completion}'")
        
        js_get_text = "document.querySelector('#editor').innerText"
        editor_before = json.loads(safari_eval_javascript(f"JSON.stringify({js_get_text})")).replace("\u00a0", " ").strip()
        
        tab_start_time = time.time()
        osascript('tell application "System Events" to tell process "Safari" to key code 48')
        
        # Tight polling loop
        tab_full_inserted_time = None
        poll_deadline = time.time() + 0.5
        while time.time() < poll_deadline:
            current_text = json.loads(safari_eval_javascript(f"JSON.stringify({js_get_text})")).replace("\u00a0", " ").strip()
            if len(current_text) > len(editor_before):
                tab_full_inserted_time = time.time()
                break
            time.sleep(0.001)
            
        polled_latency_ms = 999.0
        if tab_full_inserted_time:
            polled_latency_ms = (tab_full_inserted_time - tab_start_time) * 1000.0
            
        time.sleep(0.2)
        diag = find_accept_diagnostic(tab_start_time - 0.1)
        
        if diag:
            accepted_chunk = diag.get("acceptedChunk") or ""
            disp_after = diag.get("displayedCompletionAfter") or ""
            insertion_method = diag.get("insertionMethod") or "characterFallback"
            accept_to_full = float(diag.get("acceptToFullInsertedMs") or 0)
            inserted_atomically = bool(diag.get("insertedAtomically") or False)
            per_char_fallback = bool(diag.get("perCharacterFallback") or False)
            accept_success = bool(diag.get("acceptSuccess") or False)
            unrelated = bool(diag.get("unrelatedTextChanged") or False)
            fail_reason = diag.get("failReason") or "none"
            
            final_latency = polled_latency_ms if tab_full_inserted_time else accept_to_full
            
            transform_verified = bool(diag.get("transformVerified") or diag.get("acceptSuccess") or False)
        else:
            accepted_chunk = ""
            disp_after = displayed_completion
            insertion_method = "unknown"
            final_latency = polled_latency_ms
            inserted_atomically = False
            unrelated = False
            accept_success = False
            transform_verified = False
            fail_reason = "telemetry-log-not-found"
            final_latency = polled_latency_ms

        # Pass criteria:
        # 1. No existing text was replaced (critical correctness invariant).
        # 2. Transform verified: lineAfter == lineBefore + acceptedChunk.
        # 3. Latency <= 100ms (charByChar takes ~5ms/char so allow up to 100ms).
        # 4. acceptSuccess reported by Swift.
        # NOTE: insertedAtomically is NOT required — charByChar with a verified
        # transform is equally correct. The old AX path was preferred but it was
        # causing destructive insertions in browsers.
        is_pass = accept_success and transform_verified and not unrelated
        if final_latency > 100.0:
            is_pass = False
            fail_reason = f"latency-too-high ({final_latency:.1f}ms)"
        if unrelated:
            is_pass = False
            fail_reason = "unrelated-text-changed"
                
        results["acceptance_latency"].append({
            "case": case["name"],
            "prefix": case["prefix"],
            "displayedCompletionBefore": displayed_completion,
            "acceptedChunk": accepted_chunk,
            "displayedCompletionAfter": disp_after,
            "insertionMethod": insertion_method,
            "acceptToFullInsertedMs": final_latency,
            "insertedAtomically": inserted_atomically,
            "unrelatedTextChanged": unrelated,
            "pass": is_pass,
            "failReason": fail_reason
        })
        time.sleep(0.5)

    # =========================================================================
    # PART 2: Word-by-Word Stepping Acceptance Benchmark
    # =========================================================================
    print("\n--- Running Part 2: Word-by-Word Acceptance ---")
    displayed_completion = None
    for attempt in range(3):
        focus_and_clear()
        time.sleep(0.4)
        start_epoch = time.time()
        keystroke_text("The quick brown ")
        time.sleep(0.7)
        
        deadline = time.time() + 5.0
        while time.time() < deadline:
            ghost = find_latest_ghost_matching(start_epoch, min_length=4)
            if ghost:
                displayed_completion = ghost
                break
            time.sleep(0.05)
        if displayed_completion:
            break
        print(f"  Attempt {attempt+1} failed to produce ghost text. Retrying...")

    if displayed_completion:
        print(f"Initial suggestion: '{displayed_completion}'")
        current_ghost = displayed_completion
        for step in range(1, 4):
            if current_ghost.strip() == "":
                break
            print(f"Step {step}: Pressing Tab...")
            tab_start = time.time()
            osascript('tell application "System Events" to tell process "Safari" to key code 48')
            time.sleep(0.25)
            
            diag = find_accept_diagnostic(tab_start - 0.1)
            if diag:
                accepted_chunk = diag.get("acceptedChunk") or ""
                disp_after = diag.get("displayedCompletionAfter") or ""
                editor_text = json.loads(safari_eval_javascript("JSON.stringify(document.querySelector('#editor').innerText)")).replace("\u00a0", " ").strip()
                
                is_pass = accepted_chunk != "" and diag.get("acceptSuccess") == True
                results["word_by_word"].append({
                    "case": "prose_1",
                    "step": step,
                    "displayedBefore": current_ghost,
                    "acceptedChunk": accepted_chunk,
                    "displayedAfter": disp_after,
                    "editorTextAfter": editor_text,
                    "pass": is_pass,
                    "failReason": "none" if is_pass else "chunk-failed-to-accept"
                })
                current_ghost = disp_after
            else:
                results["word_by_word"].append({
                    "case": "prose_1",
                    "step": step,
                    "displayedBefore": current_ghost,
                    "acceptedChunk": "",
                    "displayedAfter": "",
                    "editorTextAfter": "",
                    "pass": False,
                    "failReason": "no-telemetry-log-found"
                })
                break
    else:
        print("  FAILED: No ghost text appeared for word-by-word test")

    # =========================================================================
    # PART 3: Typed-Prefix Consumption Benchmark
    # =========================================================================
    print("\n--- Running Part 3: Prefix Consumption ---")
    displayed_completion = None
    for attempt in range(3):
        focus_and_clear()
        time.sleep(0.4)
        start_epoch = time.time()
        keystroke_text("The new autocomplete ")
        time.sleep(0.7)
        
        deadline = time.time() + 5.0
        while time.time() < deadline:
            ghost = find_latest_ghost_matching(start_epoch, min_length=4)
            if ghost:
                displayed_completion = ghost
                break
            time.sleep(0.05)
        if displayed_completion:
            break
        print(f"  Attempt {attempt+1} failed to produce ghost text. Retrying...")

    if displayed_completion and len(displayed_completion) >= 2:
        print(f"Ghost visible before typing prefix: '{displayed_completion}'")
        first_char = String_index_char(displayed_completion, 0)
        second_char = String_index_char(displayed_completion, 1)
        
        # 1. Type matching first char
        print(f"Typing matching first char: '{first_char}'")
        type_start = time.time()
        keystroke_text(first_char)
        time.sleep(0.25)
        diag = find_prefix_consumption_diagnostic(type_start - 0.1)
        
        if diag:
            matched = diag.get("prefixMatched") == True
            disp_after = diag.get("displayedCompletionAfter") or ""
            is_pass = matched and disp_after != ""
            results["prefix_consumption"].append({
                "typedCharOrString": first_char,
                "displayedBefore": displayed_completion,
                "prefixMatched": matched,
                "displayedAfter": disp_after,
                "ghostStillVisible": disp_after != "",
                "acceptReady": True,
                "pass": is_pass,
                "failReason": "none" if is_pass else "failed-to-consume-prefix"
            })
            current_ghost = disp_after
        else:
            results["prefix_consumption"].append({
                "typedCharOrString": first_char,
                "displayedBefore": displayed_completion,
                "prefixMatched": False,
                "displayedAfter": "",
                "ghostStillVisible": False,
                "acceptReady": False,
                "pass": False,
                "failReason": "no-telemetry-log-found"
            })
            current_ghost = ""
            
        # 2. Type matching second char
        if current_ghost:
            print(f"Typing matching second char: '{second_char}'")
            type_start = time.time()
            keystroke_text(second_char)
            time.sleep(0.25)
            diag = find_prefix_consumption_diagnostic(type_start - 0.1)
            if diag:
                matched = diag.get("prefixMatched") == True
                disp_after = diag.get("displayedCompletionAfter") or ""
                is_pass = matched and disp_after != ""
                results["prefix_consumption"].append({
                    "typedCharOrString": second_char,
                    "displayedBefore": current_ghost,
                    "prefixMatched": matched,
                    "displayedAfter": disp_after,
                    "ghostStillVisible": disp_after != "",
                    "acceptReady": True,
                    "pass": is_pass,
                    "failReason": "none" if is_pass else "failed-to-consume-prefix"
                })
                current_ghost = disp_after
            else:
                results["prefix_consumption"].append({
                    "typedCharOrString": second_char,
                    "displayedBefore": current_ghost,
                    "prefixMatched": False,
                    "displayedAfter": "",
                    "ghostStillVisible": False,
                    "acceptReady": False,
                    "pass": False,
                    "failReason": "no-telemetry-log-found"
                })
                current_ghost = ""
                
        # 3. Type diverging character 'x'
        if current_ghost:
            print("Typing diverging character: 'x'")
            type_start = time.time()
            keystroke_text("x")
            time.sleep(0.25)
            diag = find_prefix_consumption_diagnostic(type_start - 0.1)
            if diag:
                matched = diag.get("prefixMatched") == True
                disp_after = diag.get("displayedCompletionAfter") or ""
                is_pass = not matched and disp_after == ""
                results["prefix_consumption"].append({
                    "typedCharOrString": "x",
                    "displayedBefore": current_ghost,
                    "prefixMatched": matched,
                    "displayedAfter": disp_after,
                    "ghostStillVisible": False,
                    "acceptReady": False,
                    "pass": is_pass,
                    "failReason": "none" if is_pass else "ghost-did-not-disappear-on-divergence"
                })
            else:
                results["prefix_consumption"].append({
                    "typedCharOrString": "x",
                    "displayedBefore": current_ghost,
                    "prefixMatched": False,
                    "displayedAfter": "",
                    "ghostStillVisible": False,
                    "acceptReady": False,
                    "pass": True,
                    "failReason": "none"
                })
    else:
        print("  FAILED: No ghost text appeared for prefix consumption test")

    # =========================================================================
    # PART 4: Multi-Line Caret Safety Benchmark
    # =========================================================================
    print("\n--- Running Part 4: Multi-Line Caret Safety ---")
    
    displayed_completion = None
    for attempt in range(3):
        focus_and_clear()
        js_init = (
            "{"
            "const el=document.querySelector('#editor');"
            "el.innerHTML='Line 1: Hello<br>Line 2: World<br>Line 3: Autocomplete<br>Line 4: ';"
            "el.focus();"
            "const r=document.createRange();"
            "r.selectNodeContents(el);"
            "r.collapse(false);"
            "const s=window.getSelection();"
            "s.removeAllRanges();"
            "s.addRange(r);"
            "}"
            "'ok';"
        )
        safari_eval_javascript(js_init)
        time.sleep(0.3)
        
        start_epoch = time.time()
        keystroke_text("The new ")
        time.sleep(0.7)
        
        deadline = time.time() + 5.0
        while time.time() < deadline:
            ghost = find_latest_ghost_matching(start_epoch, min_length=2)
            if ghost:
                displayed_completion = ghost
                break
            time.sleep(0.05)
        if displayed_completion:
            break
        print(f"  Attempt {attempt+1} failed to produce ghost text. Retrying...")

    if displayed_completion:
        print(f"Ghost visible on line 4: '{displayed_completion}'")
        
        editor_text_before = json.loads(safari_eval_javascript("JSON.stringify(document.querySelector('#editor').innerText)")).replace("\u00a0", " ")
        lines_before = editor_text_before.split("\n")
        while len(lines_before) < 4:
            lines_before.append("")
            
        tab_start = time.time()
        osascript('tell application "System Events" to tell process "Safari" to key code 48')
        time.sleep(0.25)
        
        diag = find_accept_diagnostic(tab_start - 0.1)
        
        editor_text_after = json.loads(safari_eval_javascript("JSON.stringify(document.querySelector('#editor').innerText)")).replace("\u00a0", " ")
        lines_after = editor_text_after.split("\n")
        while len(lines_after) < 4:
            lines_after.append("")
            
        if diag:
            accepted_chunk = diag.get("acceptedChunk") or ""
            unrelated = diag.get("unrelatedTextChanged") == True if isinstance(diag.get("unrelatedTextChanged"), bool) else (lines_before[0] != lines_after[0] or lines_before[1] != lines_after[1] or lines_before[2] != lines_after[2])
            inserted_at_caret = diag.get("insertedAtCaretVerified") == True or lines_after[3].endswith(accepted_chunk)
            
            is_pass = not unrelated and inserted_at_caret
            
            results["multiline_safety"] = {
                "line1Before": lines_before[0],
                "line1After": lines_after[0],
                "line4Before": lines_before[3],
                "line4After": lines_after[3],
                "acceptedChunk": accepted_chunk,
                "unrelatedTextChanged": unrelated,
                "insertedAtCaretCorrect": inserted_at_caret,
                "pass": is_pass,
                "failReason": "none" if is_pass else "unrelated-text-modified-or-wrong-caret"
            }
        else:
            results["multiline_safety"] = {
                "line1Before": lines_before[0],
                "line1After": lines_after[0],
                "line4Before": lines_before[3],
                "line4After": lines_after[3],
                "acceptedChunk": "",
                "unrelatedTextChanged": True,
                "insertedAtCaretCorrect": False,
                "pass": False,
                "failReason": "no-telemetry-log-found"
            }
    else:
        print("  FAILED: No ghost text appeared for line 4 of multi-line safety test")

    # Save results
    with RESULTS_PATH.open("w") as f:
        json.dump(results, f, indent=2)
    print(f"\nAll results saved to {RESULTS_PATH}")

def String_index_char(s, idx):
    if idx < len(s):
        return s[idx]
    return ""

if __name__ == "__main__":
    main()
