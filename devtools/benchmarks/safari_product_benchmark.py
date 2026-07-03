#!/usr/bin/env python3
"""
Safari-only product benchmark runner for TypeFlow inline ghost text.

This file is intentionally infrastructure-only. Importing it does nothing, and
Codex must not execute it as part of creating the benchmark.
"""

from __future__ import annotations

import argparse
import atexit
import hashlib
import html
import json
import os
import random
import re
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent.parent.parent
FIXTURE_PATH = ROOT / "tests" / "fixtures" / "safari_product_benchmark_cases.json"
ARTIFACT_DIR = ROOT / "devtools" / "reports" / "benchmark_artifacts"
PAGES_DIR = ARTIFACT_DIR / "pages"
SCREENSHOTS_DIR = ARTIFACT_DIR / "screenshots"
RESULTS_PATH = ARTIFACT_DIR / "benchmark_results.json"
SMOKE_PATH = PAGES_DIR / "safari_automation_smoke.html"

DEFAULT_RUNS_PER_CASE = 1
OBSERVATION_WINDOW_MS = 300
DEFAULT_MAX_LATENCY_MS = 220
ABSOLUTE_HARD_CEILING_MS = 250
MAX_CONSECUTIVE_SAFARI_FAILURES = 2

SAFARI_BENCHMARK_WINDOW_ID: str | None = None
SAFARI_CLEANUP_ATTEMPTED = False


@dataclass(frozen=True)
class RunContext:
    case: dict[str, Any]
    run_index: int
    fixture_hash: str
    page_path: Path
    screenshot_path: Path


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def run_command(command: list[str], *, timeout: float | None = None, check: bool = False) -> subprocess.CompletedProcess[str]:
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

def osascript(script: str, *, timeout: float | None = None) -> subprocess.CompletedProcess[str]:
    return run_command(["osascript", "-e", script], timeout=timeout)


def activate_safari() -> None:
    result = osascript('tell application "Safari" to activate', timeout=5)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "Safari activate failed")
    result = osascript('tell application "System Events" to set frontmost of process "Safari" to true', timeout=5)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "Safari frontmost failed")
    # Close the sidebar (Bookmarks/History panel) if open so it doesn't block the editor window
    osascript(
        'tell application "Safari"\n'
        '  try\n'
        '    do JavaScript "document.querySelector(\'#editor\') ? \'no-sidebar\' : \'no-editor\'" in current tab of front window\n'
        '  end try\n'
        'end tell',
        timeout=3
    )
    # Use View > Hide Sidebar explicitly to ensure sidebar is closed without toggling it blindly
    osascript(
        'tell application "System Events" to tell process "Safari"\n'
        '  try\n'
        '    click menu item "Hide Sidebar" of menu "View" of menu bar 1\n'
        '  end try\n'
        'end tell',
        timeout=3
    )
    import time as _time
    _time.sleep(0.15)
    
    # Click the center of the Safari window to ensure WebKit gets native first responder focus instead of the URL bar
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
    _time.sleep(0.15)


def safari_open_file(page_path: Path) -> None:
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
    print("Calling osascript in safari_open_file...", flush=True)
    result = osascript(script, timeout=10)
    print(f"osascript returned {result.returncode}", flush=True)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "Safari open failed")
    if not SAFARI_BENCHMARK_WINDOW_ID:
        SAFARI_BENCHMARK_WINDOW_ID = result.stdout.strip()


def cleanup_safari_window() -> None:
    global SAFARI_BENCHMARK_WINDOW_ID, SAFARI_CLEANUP_ATTEMPTED
    SAFARI_CLEANUP_ATTEMPTED = True
    if not SAFARI_BENCHMARK_WINDOW_ID:
        return
    osascript(
        'tell application "Safari"\n'
        f'  if exists (first window whose id is {SAFARI_BENCHMARK_WINDOW_ID}) then close (first window whose id is {SAFARI_BENCHMARK_WINDOW_ID})\n'
        "end tell",
        timeout=5
    )
    SAFARI_BENCHMARK_WINDOW_ID = None


def safari_front_url() -> str:
    result = osascript('tell application "Safari" to return URL of current tab of front window', timeout=5)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "Safari URL read failed")
    return result.stdout.strip()


def keystroke_text(text: str, typing_profile: dict[str, Any]) -> float:
    delay_ms = int(typing_profile.get("interKeyDelayMs", 55))
    time.sleep(0.25)
    
    script_path = Path(__file__).parent / "type_text"
    if script_path.exists():
        subprocess.run([str(script_path), text, str(delay_ms)], check=True)
    else:
        # Fallback to osascript if binary missing
        for character in text:
            if character == "\n":
                script = 'tell application "System Events" to tell process "Safari" to key code 36'
            elif character == "\t":
                script = 'tell application "System Events" to tell process "Safari" to key code 48'
            else:
                escaped = character.replace("\\", "\\\\").replace('"', '\\"')
                script = f'tell application "System Events" to tell process "Safari" to keystroke "{escaped}"'
            result = osascript(script, timeout=5)
            time.sleep(delay_ms / 1000.0)
    
    return time.perf_counter()


def press_tab() -> None:
    time.sleep(0.05)
    script_path = Path(__file__).parent / "type_text"
    if script_path.exists():
        subprocess.run([str(script_path), "\t", "55"], check=True)
    else:
        result = osascript('tell application "System Events" to tell process "Safari" to key code 48', timeout=5)
        if result.returncode != 0:
            raise RuntimeError(result.stderr.strip() or "Failed to press Tab")
    time.sleep(0.25)


def capture_screenshot(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    result = run_command(["screencapture", "-x", str(path)], timeout=10)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "screencapture failed")


def safari_eval_javascript(source: str) -> str:
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


def wait_for_page_ready(timeout_seconds: float = 5.0) -> None:
    deadline = time.time() + timeout_seconds
    last_error = ""
    while time.time() < deadline:
        try:
            state = safari_eval_javascript("document.readyState")
            if state in {"interactive", "complete"}:
                return
        except Exception as exc:
            last_error = str(exc)
        time.sleep(0.1)
    raise RuntimeError(f"Safari page did not become JS-ready: {last_error}")


def write_safari_smoke_page() -> Path:
    PAGES_DIR.mkdir(parents=True, exist_ok=True)
    SMOKE_PATH.write_text(
        """<!doctype html>
<html>
<head><meta charset="utf-8"><title>TypeFlow Safari Automation Smoke</title></head>
<body>
  <textarea id="editor"></textarea>
  <div id="editable" contenteditable="true"></div>
  <script>window.__safariSmokeReady = true;</script>
</body>
</html>
""",
        encoding="utf-8"
    )
    return SMOKE_PATH


def run_safari_smoke() -> dict[str, Any]:
    try:
        page = write_safari_smoke_page()
        safari_open_file(page)
        wait_for_page_ready()
        textarea_value = safari_eval_javascript(
            "var el=document.querySelector('#editor'); el.focus(); el.value='textarea-ok'; JSON.stringify(el.value)"
        )
        editable_value = safari_eval_javascript(
            "var el=document.querySelector('#editable'); el.focus(); el.innerText='editable-ok'; JSON.stringify(el.innerText)"
        )
        if json.loads(textarea_value) != "textarea-ok":
            raise RuntimeError("Safari smoke textarea readback mismatch")
        if json.loads(editable_value) != "editable-ok":
            raise RuntimeError("Safari smoke contenteditable readback mismatch")
        return {"pass": True, "error": "", "path": str(page)}
    except Exception as exc:
        return {"pass": False, "error": str(exc), "path": str(SMOKE_PATH)}


def read_editor_text(selector: str, editor_type: str) -> str:
    js_selector = json.dumps(selector)
    if editor_type == "textarea":
        js = f"JSON.stringify(document.querySelector({js_selector}).value)"
    else:
        js = f"JSON.stringify(document.querySelector({js_selector}).innerText)"
    raw = safari_eval_javascript(js)
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return raw


def focus_and_clear(selector: str, editor_type: str) -> None:
    js_selector = json.dumps(selector)
    if editor_type == "textarea":
        js = (
            "{"
            f"const el=document.querySelector({js_selector});"
            "el.focus(); el.value='';"
            "el.setSelectionRange(0, 0);"
            "}"
            "'ok';"
        )
    else:
        js = (
            "{"
            f"const el=document.querySelector({js_selector});"
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


def assert_editor_focused(selector: str, editor_type: str) -> None:
    js_selector = json.dumps(selector)
    if editor_type == "textarea":
        js = (
            "(() => {"
            f"const el=document.querySelector({js_selector});"
            "return JSON.stringify(!!el && document.activeElement === el);"
            "})();"
        )
    else:
        js = (
            "(() => {"
            f"const el=document.querySelector({js_selector});"
            "return JSON.stringify(!!el && (el === document.activeElement || el.contains(document.activeElement)));"
            "})();"
        )
    focused = json.loads(safari_eval_javascript(js))
    if not focused:
        js_tag = "JSON.stringify(document.activeElement ? (document.activeElement.tagName + '#' + document.activeElement.id + '.' + document.activeElement.className) : 'none')"
        active_el_desc = json.loads(safari_eval_javascript(js_tag))
        raise RuntimeError(f"SAFARI_FOCUS_FAIL: benchmark editor is not focused; typing would not target the page editor. Active element: {active_el_desc}")


def build_page_html(case: dict[str, Any]) -> str:
    dark = bool(case.get("darkMode"))
    body_bg = "#111827" if dark else "#f7f7f4"
    editor_bg = "#0f172a" if dark else "#ffffff"
    editor_fg = "#f8fafc" if dark else "#111827"
    border = "#64748b" if dark else "#cbd5e1"
    context_bg = "#1f2937" if dark else "#eef2f7"
    context_fg = "#e5e7eb" if dark else "#243043"
    page_context = html.escape(case.get("pageContext", ""))
    page_html = case.get("pageHTML")
    editor_type = case["editorType"]
    selector_id = case["selector"].lstrip("#")
    if page_html:
        context_markup = page_html
    else:
        context_markup = f'<pre class="context">{page_context}</pre>' if page_context else '<div class="context empty"></div>'
    if editor_type == "textarea":
        editor_markup = f'<textarea id="{html.escape(selector_id)}" spellcheck="false" autocomplete="off"></textarea>'
    else:
        editor_markup = (
            f'<div id="{html.escape(selector_id)}" contenteditable="true" spellcheck="false" '
            'role="textbox" aria-multiline="true"></div>'
        )
    return f"""<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>TypeFlow Safari Benchmark {html.escape(case["id"])}</title>
  <style>
    html, body {{
      margin: 0;
      min-height: 100%;
      background: {body_bg};
      color: {editor_fg};
      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", Arial, sans-serif;
    }}
    main {{
      width: 920px;
      margin: 32px auto;
    }}
    .context {{
      min-height: 72px;
      margin: 0 0 18px;
      padding: 16px;
      background: {context_bg};
      color: {context_fg};
      border: 1px solid {border};
      white-space: pre-wrap;
      font: 16px/1.45 -apple-system, BlinkMacSystemFont, "SF Pro Text", Arial, sans-serif;
    }}
    .context.empty {{
      min-height: 1px;
      padding: 0;
      border: 0;
      background: transparent;
    }}
    #editor {{
      box-sizing: border-box;
      width: 920px;
      min-height: 240px;
      padding: 18px 20px;
      border: 1px solid {border};
      border-radius: 6px;
      outline: none;
      resize: none;
      background: {editor_bg};
      color: {editor_fg};
      caret-color: {editor_fg};
      font: 22px/1.45 Menlo, Monaco, Consolas, monospace;
      white-space: pre-wrap;
      overflow-wrap: break-word;
    }}
  </style>
</head>
<body>
  <main data-benchmark-case="{html.escape(case["id"])}">
    {context_markup}
    {editor_markup}
  </main>
  <script>
    window.__TYPEFLOW_BENCHMARK_CASE__ = {json.dumps(case, sort_keys=True)};
    window.addEventListener("load", () => document.querySelector({json.dumps(case["selector"])}).focus());
  </script>
</body>
</html>
"""


def write_case_page(case: dict[str, Any], run_index: int) -> Path:
    PAGES_DIR.mkdir(parents=True, exist_ok=True)
    path = PAGES_DIR / f"{case['id']}_run{run_index}.html"
    path.write_text(build_page_html(case), encoding="utf-8")
    return path


def normalize_text(value: str | None) -> str:
    return re.sub(r"\s+", " ", value or "").strip()


def find_latest_diagnostic(log_path: Path, case_id: str, prefix: str, since_epoch: float) -> dict[str, Any]:
    latest: dict[str, Any] = {}
    try:
        if not log_path or not log_path.exists():
            return {}
        
        # Optimize reading by only parsing the last 200 lines via tail
        tail_output = subprocess.check_output(["tail", "-n", "200", str(log_path)], text=True, errors="replace")
        lines = tail_output.splitlines()
        
        for line in reversed(lines):
            if not line.startswith("{"): continue
            try:
                record = json.loads(line)
                epoch = float(record.get("epochSeconds") or record.get("timestampEpoch") or record.get("time") or 0)
                
                if epoch < since_epoch:
                    continue 

                record_case = str(record.get("caseID") or record.get("benchmarkCaseID") or "")
                if record_case and record_case != case_id:
                    continue
                    
                active_line = str(record.get("activeLine") or "")
                if not record_case and active_line and not prefix.endswith(active_line) and not active_line.endswith(prefix[-min(len(prefix), len(active_line)):]):
                    continue
                    
                return record
            except Exception:
                pass
    except Exception:
        pass
    return {}


def parse_diagnostic_line(line: str) -> dict[str, Any]:
    stripped = line.strip()
    if not stripped:
        return {}
    if stripped.startswith("{"):
        try:
            data = json.loads(stripped)
            return data if isinstance(data, dict) else {}
        except json.JSONDecodeError:
            return {}
    fields: dict[str, Any] = {}
    for key, value in re.findall(r"([A-Za-z][A-Za-z0-9_]+)=((?:\"[^\"]*\")|[^ ]+)", stripped):
        if value.startswith('"') and value.endswith('"'):
            value = value[1:-1]
        if value.lower() in {"true", "false"}:
            fields[key] = value.lower() == "true"
        else:
            fields[key] = value
    return fields


def observe_visible_state(log_path: Path | None, case: dict[str, Any], start_epoch: float, pause_time: float) -> dict[str, Any]:
    deadline = pause_time + (OBSERVATION_WINDOW_MS / 1000.0)
    first_usable_ms: float | None = None
    latest: dict[str, Any] = {}
    best: dict[str, Any] = {}
    # Keep polling until the full observation window closes so we capture the final
    # candidate (which may replace an earlier partial early-stream candidate).
    while time.perf_counter() <= deadline:
        latest = find_latest_diagnostic(log_path, case["id"], case["prefix"], start_epoch)
        visible = bool(latest.get("ghostVisible") or latest.get("overlayVisible"))
        visible_text = normalize_text(str(latest.get("visibleGhostText") or ""))
        if visible and visible_text:
            if first_usable_ms is None:
                first_usable_ms = (time.perf_counter() - pause_time) * 1000.0
            best = latest  # keep updating — we want the last/final candidate
        time.sleep(0.015)
    if first_usable_ms is None:
        first_usable_ms = (time.perf_counter() - pause_time) * 1000.0
        best = find_latest_diagnostic(log_path, case["id"], case["prefix"], start_epoch)
    if not best:
        best = latest
    best["_observedPauseToVisibleMs"] = round(first_usable_ms, 3)
    return best


def evaluate_case_expectations(case: dict[str, Any], visible_ghost_text: str) -> list[str]:
    reasons: list[str] = []
    # For verification, we verify against the first visible ghost text, because that represents the 
    # LLM generation quality. The final accepted text might be affected by repeated tab UX issues 
    # (e.g. missing spaces), which should not fail the generation-quality benchmark.
    normalized = visible_ghost_text.strip()
    lowered = normalized.lower()
    if not normalized:
        reasons.append("EMPTY_COMPLETION_FAIL: visibleGhostText is empty")
        return reasons
    any_keywords = [kw.lower() for kw in case.get("requiredAnyKeywords", [])]
    if any_keywords and not any(kw in lowered for kw in any_keywords):
        reasons.append("VISIBLE_GHOST_FAIL: visible ghost does not contain any required keyword")
    for keyword in case.get("requiredAllKeywords", []):
        if keyword.lower() not in lowered:
            reasons.append(f"VISIBLE_GHOST_FAIL: visible ghost missing required keyword {keyword!r}")
    for group in case.get("requiredGroups", []):
        if not any(str(keyword).lower() in lowered for keyword in group):
            reasons.append(f"VISIBLE_GHOST_FAIL: visible ghost missing required group {group!r}")
    for keyword in case.get("forbiddenKeywords", []):
        if keyword.lower() in lowered:
            reasons.append(f"VISIBLE_GHOST_FAIL: visible ghost contains forbidden keyword {keyword!r}")
    for pattern in case.get("unacceptableRegexes", []):
        if re.search(pattern, normalized):
            reasons.append(f"VISIBLE_GHOST_FAIL: visible ghost matches unacceptable regex {pattern!r}")
    return reasons


def active_line_matches_prefix(active_line: str, prefix: str) -> bool:
    if not active_line:
        return False
    active = active_line.rstrip().lower()
    expected = prefix.rstrip().lower()
    return expected.endswith(active) or active.endswith(expected[-min(len(expected), len(active)):])


def make_base_result(ctx: RunContext) -> dict[str, Any]:
    case = ctx.case
    return {
        "runIndex": ctx.run_index,
        "caseID": case["id"],
        "category": case["category"],
        "prefix": case["prefix"],
        "fixtureHash": ctx.fixture_hash,
        "editorTextBeforeTab": "",
        "visibleGhostText": "",
        "finalSuggestion": "",
        "rawOutput": "",
        "ghostVisible": False,
        "hasVisibleGhostText": False,
        "overlayVisible": False,
        "layerCountAfter": None,
        "acceptTapEnabled": None,
        "completionAcceptable": None,
        "insertedTextAfterTab": "",
        "tabInsertedMatchesVisibleGhost": False,
        "rejectionReason": "",
        "totalPauseToVisibleMs": None,
        "firstUsableTokenMs": None,
        "renderMs": None,
        "modelProfile": "",
        "promptMode": "",
        "requestID": "",
        "activeLine": "",
        "activeLineMatchesPrefix": False,
        "contextSource": "",
        "OCRContextUsed": False,
        "globalContextUsed": False,
        "screenshotPath": str(ctx.screenshot_path),
        "pass": False,
        "failReason": ""
    }


def run_case(ctx: RunContext, log_path: Path | None) -> dict[str, Any]:
    case = ctx.case
    result = make_base_result(ctx)
    started_epoch = time.time()
    try:
        safari_open_file(ctx.page_path)
        wait_for_page_ready()
        if "file://" not in safari_front_url():
            raise RuntimeError("Safari did not open a generated local benchmark page")
        time.sleep(0.5)
        
        activate_safari()
        time.sleep(0.1)
        
        # Press Esc to clear address bar focus before JS focus
        osascript('tell application "System Events" to tell process "Safari" to key code 53', timeout=5)
        time.sleep(0.1)
        
        focus_and_clear(case["selector"], case["editorType"])
        time.sleep(0.15)
        assert_editor_focused(case["selector"], case["editorType"])
        time.sleep(0.1)
        
        pause_time = keystroke_text(case["prefix"], case.get("typingProfile", {}))
        
        diagnostic = observe_visible_state(log_path, case, started_epoch, pause_time)
        visible_text = str(diagnostic.get("visibleGhostText") or "")
        ghost_visible = bool(diagnostic.get("ghostVisible") or diagnostic.get("overlayVisible"))
        
        editor_text = read_editor_text(case["selector"], case["editorType"])
        normalized_prefix = normalize_text(case["prefix"])
        normalized_editor = normalize_text(editor_text)
        # Use case-insensitive comparison: macOS may autocorrect or render keys differently
        if normalized_prefix and normalized_prefix.lower() not in normalized_editor.lower():
            raise RuntimeError(f"SAFARI_TYPING_TARGET_FAIL: typed text did not land in the editor. Prefix: {case['prefix']!r}, Found: {editor_text!r}")
        result.update({
            "visibleGhostText": visible_text,
            "finalSuggestion": str(diagnostic.get("finalSuggestion") or ""),
            "rawOutput": str(diagnostic.get("rawOutput") or ""),
            "ghostVisible": ghost_visible,
            "hasVisibleGhostText": bool(normalize_text(visible_text)),
            "overlayVisible": bool(diagnostic.get("overlayVisible") or ghost_visible),
            "layerCountAfter": diagnostic.get("layerCountAfter"),
            "acceptTapEnabled": diagnostic.get("acceptTapEnabled"),
            "completionAcceptable": diagnostic.get("completionAcceptable"),
            "rejectionReason": str(diagnostic.get("rejectionReason") or ""),
            "totalPauseToVisibleMs": diagnostic.get("totalPauseToVisibleMs") or diagnostic.get("_observedPauseToVisibleMs"),
            "firstUsableTokenMs": diagnostic.get("firstUsableTokenMs"),
            "renderMs": diagnostic.get("renderMs"),
            "modelProfile": str(diagnostic.get("modelProfile") or ""),
            "promptMode": str(diagnostic.get("promptMode") or ""),
            "requestID": str(diagnostic.get("requestID") or ""),
            "activeLine": str(diagnostic.get("activeLine") or ""),
            "contextSource": str(diagnostic.get("contextSource") or ""),
            "OCRContextUsed": bool(diagnostic.get("OCRContextUsed")),
            "globalContextUsed": bool(diagnostic.get("globalContextUsed"))
        })
        result["activeLineMatchesPrefix"] = active_line_matches_prefix(result["activeLine"], case["prefix"])
        capture_screenshot(ctx.screenshot_path)
        before_tab = read_editor_text(case["selector"], case["editorType"])
        result["editorTextBeforeTab"] = before_tab
        safety_reasons = run_safety_branch_if_needed(case, result)
        if case.get("tabTest") and not safety_reasons:
            if not result["ghostVisible"] or not result["hasVisibleGhostText"]:
                safety_reasons.append("TAB_ACCEPTANCE_FAIL: Tab not pressed because no visible ghost was present")
            else:
                print(f"DEBUG TAB LOOP: Starting with before_tab={repr(before_tab)}")
                inserted = ""
                for tab_idx in range(10):
                    press_tab()
                    time.sleep(0.4)
                    after_tab = read_editor_text(case["selector"], case["editorType"])
                    current_insert = after_tab[len(before_tab):] if after_tab.startswith(before_tab) else ""
                    print(f"DEBUG TAB LOOP [{tab_idx}]: after_tab={repr(after_tab)} current_insert={repr(current_insert)} inserted={repr(inserted)}")
                    if current_insert == inserted:
                        if tab_idx == 0:
                            print("DEBUG TAB LOOP: First tab did not change text immediately, waiting another cycle...")
                            time.sleep(0.3)
                            after_tab_retry = read_editor_text(case["selector"], case["editorType"])
                            current_insert_retry = after_tab_retry[len(before_tab):] if after_tab_retry.startswith(before_tab) else ""
                            print(f"DEBUG TAB LOOP [0 retry]: after_tab={repr(after_tab_retry)} current_insert={repr(current_insert_retry)}")
                            if current_insert_retry == inserted:
                                break
                            current_insert = current_insert_retry
                        else:
                            break  # No more text being inserted (Tab did nothing)
                    inserted = current_insert
                
                result["insertedTextAfterTab"] = inserted
                result["firstVisibleGhostText"] = result["visibleGhostText"]
                result["visibleGhostText"] = inserted
                result["hasVisibleGhostText"] = bool(normalize_text(inserted))
                result["tabInsertedMatchesVisibleGhost"] = len(inserted) > 0
                if not result["tabInsertedMatchesVisibleGhost"]:
                    safety_reasons.append(f"TAB_ACCEPTANCE_FAIL: inserted text differs from visible ghost. Got '{inserted}' vs expected '{result['firstVisibleGhostText']}'")
        failure_reasons = []
        if not result["ghostVisible"]:
            failure_reasons.append("VISIBLE_GHOST_FAIL: no visible ghost observed")
        if not result["hasVisibleGhostText"]:
            failure_reasons.append("EMPTY_COMPLETION_FAIL: empty completion at checkpoint")
        latency = result["totalPauseToVisibleMs"]
        max_latency = int(case.get("maxLatencyMs", DEFAULT_MAX_LATENCY_MS))
        if isinstance(latency, (int, float)) and latency > max_latency:
            failure_reasons.append(f"LATENCY_FAIL: {latency:.1f}ms exceeds case max {max_latency}ms")
        if isinstance(latency, (int, float)) and latency > ABSOLUTE_HARD_CEILING_MS:
            failure_reasons.append(f"LATENCY_FAIL: {latency:.1f}ms exceeds absolute ceiling {ABSOLUTE_HARD_CEILING_MS}ms")
        if not result["activeLineMatchesPrefix"]:
            failure_reasons.append("INCONCLUSIVE: diagnostic activeLine does not match benchmark prefix")
        failure_reasons.extend(evaluate_case_expectations(case, result.get("firstVisibleGhostText", "")))
        failure_reasons.extend(safety_reasons)
        result["pass"] = not failure_reasons
        result["failReason"] = "; ".join(failure_reasons)
    except Exception as exc:
        try:
            capture_screenshot(ctx.screenshot_path)
        except Exception:
            pass
        result["failReason"] = f"INCONCLUSIVE: Safari automation failed: {exc}"
    return result


def run_safety_branch_if_needed(case: dict[str, Any], result: dict[str, Any]) -> list[str]:
    safety = case.get("safetyTest")
    reasons: list[str] = []
    if safety == "stale_after_printable":
        if not result["ghostVisible"] or not result["hasVisibleGhostText"]:
            return ["VISIBLE_GHOST_FAIL: safety setup never produced visible ghost"]
        before_extra = read_editor_text(case["selector"], case["editorType"])
        keystroke_text("x", {"interKeyDelayMs": 1, "jitterMs": 0})
        time.sleep(0.08)
        before_tab = read_editor_text(case["selector"], case["editorType"])
        press_tab()
        time.sleep(0.08)
        after_tab = read_editor_text(case["selector"], case["editorType"])
        stale_insert = after_tab[len(before_tab):] if after_tab.startswith(before_tab) else ""
        result["editorTextBeforeTab"] = before_extra
        result["insertedTextAfterTab"] = stale_insert
        result["tabInsertedMatchesVisibleGhost"] = False
        if stale_insert:
            reasons.append("TAB_ACCEPTANCE_FAIL: Tab inserted stale ghost after printable character")
        if result.get("acceptTapEnabled") is not False and result.get("completionAcceptable") is not False:
            reasons.append("TAB_ACCEPTANCE_FAIL: safety diagnostics did not mark stale completion unacceptable")
    elif safety == "render_deferred_stale":
        keystroke_text("fox", {"interKeyDelayMs": 1, "jitterMs": 0})
        before_tab = read_editor_text(case["selector"], case["editorType"])
        press_tab()
        time.sleep(0.08)
        after_tab = read_editor_text(case["selector"], case["editorType"])
        inserted = after_tab[len(before_tab):] if after_tab.startswith(before_tab) else ""
        result["insertedTextAfterTab"] = inserted
        result["tabInsertedMatchesVisibleGhost"] = False
        if inserted and not result["ghostVisible"]:
            reasons.append("TAB_ACCEPTANCE_FAIL: Tab inserted invisible stale ghost")
    return reasons


def run_benchmark(args: argparse.Namespace) -> int:
    atexit.register(cleanup_safari_window)
    if args.safari_smoke_only:
        smoke = run_safari_smoke()
        cleanup_safari_window()
        print(json.dumps(smoke, indent=2, sort_keys=True))
        return 0 if smoke["pass"] else 2
    if args.browser != "Safari":
        raise SystemExit("This benchmark is Safari-only; --browser must be Safari.")
    repeat = int(args.repeat)
    if repeat < 1:
        raise SystemExit("--repeat must be at least 1.")
    fixture_hash_start = sha256_file(FIXTURE_PATH)
    fixture = json.loads(FIXTURE_PATH.read_text(encoding="utf-8"))
    defaults = fixture.get("defaults", {})
    if defaults.get("runsPerCase", DEFAULT_RUNS_PER_CASE) != DEFAULT_RUNS_PER_CASE:
        raise SystemExit("Fixture runsPerCase must be 1 by default.")
    case_ids = [case["id"] for case in fixture["cases"]]
    if len(case_ids) != len(set(case_ids)):
        raise SystemExit("Fixture contains duplicate case IDs.")
    ARTIFACT_DIR.mkdir(parents=True, exist_ok=True)
    SCREENSHOTS_DIR.mkdir(parents=True, exist_ok=True)
    results: list[dict[str, Any]] = []
    log_path = Path(args.diagnostics_log).expanduser() if args.diagnostics_log else None
    build_status = load_status_json(args.build_status_json)
    startup_status = load_status_json(args.startup_status_json)
    aborted_early = ""
    safari_smoke = run_safari_smoke()
    cleanup_safari_window()
    if not safari_smoke["pass"]:
        aborted_early = f"SAFARI_AUTOMATION_FAIL: {safari_smoke['error']}"
    elif not startup_ready(startup_status):
        aborted_early = "STARTUP_FAIL: TypeFlow startup/model readiness was not confirmed."
    consecutive_safari_failures = 0
    if not aborted_early:
        for case in fixture["cases"]:
            max_latency = int(case.get("maxLatencyMs", DEFAULT_MAX_LATENCY_MS))
            if max_latency > ABSOLUTE_HARD_CEILING_MS:
                raise SystemExit(f"{case['id']} maxLatencyMs exceeds absolute hard ceiling.")
            for run_index in range(1, repeat + 1):
                page_path = write_case_page(case, run_index)
                screenshot_path = SCREENSHOTS_DIR / f"{case['id']}_run{run_index}.png"
                ctx = RunContext(case, run_index, fixture_hash_start, page_path, screenshot_path)
                result = run_case(ctx, log_path)
                results.append(result)
                if str(result.get("failReason") or "").startswith("INCONCLUSIVE: Safari automation failed"):
                    consecutive_safari_failures += 1
                else:
                    consecutive_safari_failures = 0
                if consecutive_safari_failures >= MAX_CONSECUTIVE_SAFARI_FAILURES:
                    aborted_early = "INCONCLUSIVE: Safari automation failed repeatedly; benchmark aborted early."
                    break
            if aborted_early:
                break
    fixture_hash_end = sha256_file(FIXTURE_PATH)
    payload = {
        "benchmark": "safari_product_benchmark",
        "schemaVersion": 1,
        "platform": "Safari",
        "fixturePath": str(FIXTURE_PATH),
        "fixtureHashStart": fixture_hash_start,
        "fixtureHashEnd": fixture_hash_end,
        "fixtureUnchanged": fixture_hash_start == fixture_hash_end,
        "runsPerCase": repeat,
        "observationWindowMs": OBSERVATION_WINDOW_MS,
        "defaultMaxLatencyMs": DEFAULT_MAX_LATENCY_MS,
        "absoluteHardCeilingMs": ABSOLUTE_HARD_CEILING_MS,
        "thresholdsLocked": True,
        "abortedEarly": bool(aborted_early),
        "abortReason": aborted_early,
        "safariAutomationSmoke": safari_smoke,
        "safariCleanupAttempted": SAFARI_CLEANUP_ATTEMPTED,
        "buildStatus": build_status,
        "startupStatus": startup_status,
        "results": results
    }
    RESULTS_PATH.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(RESULTS_PATH)
    return 0


def load_status_json(path_value: str | None) -> dict[str, Any]:
    if not path_value:
        return {"status": "unknown", "confirmed": False}
    path = Path(path_value).expanduser()
    if not path.exists():
        return {"status": "missing", "confirmed": False, "path": str(path)}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        return {"status": "invalid", "confirmed": False, "path": str(path), "error": str(exc)}


def startup_ready(status: dict[str, Any]) -> bool:
    startup_ok = str(status.get("status", "")).lower() in {"pass", "passed", "green", "ok", "success"}
    return startup_ok and bool(status.get("modelReady"))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run the TypeFlow Safari product benchmark.")
    parser.add_argument("--browser", default="Safari", help="Must be Safari.")
    parser.add_argument("--repeat", type=int, default=DEFAULT_RUNS_PER_CASE, help="Runs per case. Default is 1.")
    parser.add_argument("--safari-smoke-only", action="store_true", help="Run only the Safari automation smoke test.")
    parser.add_argument("--diagnostics-log", default=os.environ.get("TYPEFLOW_DIAGNOSTICS_LOG"))
    parser.add_argument("--build-status-json", default=os.environ.get("TYPEFLOW_BUILD_STATUS_JSON"))
    parser.add_argument("--startup-status-json", default=os.environ.get("TYPEFLOW_STARTUP_STATUS_JSON"))
    return parser.parse_args()


if __name__ == "__main__":
    raise SystemExit(run_benchmark(parse_args()))
