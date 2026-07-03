#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
ARTIFACT_DIR="$ROOT_DIR/devtools/reports/benchmark_artifacts"
FIXTURE="$ROOT_DIR/tests/fixtures/safari_product_benchmark_cases.json"
BUILD_STATUS_JSON="$ARTIFACT_DIR/build_status.json"
STARTUP_STATUS_JSON="$ARTIFACT_DIR/startup_status.json"
RESULTS_JSON="$ARTIFACT_DIR/benchmark_results.json"
REPORT_MD="$ARTIFACT_DIR/benchmark_report.md"
DERIVED_DATA="$ARTIFACT_DIR/DerivedData"
BUILD_LOG="$ARTIFACT_DIR/xcodebuild_build.log"
TEST_LOG="$ARTIFACT_DIR/xcodebuild_test.log"
STARTUP_LOG="$ARTIFACT_DIR/typeflow_startup.log"
SCHEME="${TYPEFLOW_XCODE_SCHEME:-TypeFlow}"
PROJECT="${TYPEFLOW_XCODE_PROJECT:-$ROOT_DIR/TypeFlow.xcodeproj}"
DIAGNOSTICS_LOG="${TYPEFLOW_DIAGNOSTICS_LOG:-$ARTIFACT_DIR/typeflow_diagnostics.log}"
TYPEFLOW_MODEL_READY_FILE="${TYPEFLOW_MODEL_READY_FILE:-$HOME/Library/Application Support/TypeFlow/model_ready.json}"
TYPEFLOW_PIDS_BEFORE="$(pgrep -x "TypeFlow" 2>/dev/null || true)"
BENCHMARK_TYPEFLOW_PIDS=""

mkdir -p "$ARTIFACT_DIR"

cleanup() {
  if [[ -n "$BENCHMARK_TYPEFLOW_PIDS" ]]; then
    while read -r pid; do
      [[ -z "$pid" ]] && continue
      kill "$pid" 2>/dev/null || true
    done <<< "$BENCHMARK_TYPEFLOW_PIDS"
  fi
}

trap cleanup EXIT INT TERM

hash_fixture() {
  shasum -a 256 "$FIXTURE" | awk '{print $1}'
}

write_build_status() {
  local status="$1"
  local tests_status="$2"
  local build_status="$3"
  local xcode_gui_confirmed="${TYPEFLOW_XCODE_GUI_CONFIRMED:-false}"
  python3 - "$BUILD_STATUS_JSON" "$status" "$tests_status" "$build_status" "$xcode_gui_confirmed" <<'PY'
import json
import sys
path, status, tests_status, build_status, xcode_gui_confirmed = sys.argv[1:]
payload = {
    "status": status,
    "swiftTests": tests_status,
    "cliXcodebuild": build_status,
    "xcodeGUIConfirmed": xcode_gui_confirmed.lower() == "true",
}
open(path, "w", encoding="utf-8").write(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY
}

write_startup_status() {
  local status="$1"
  local app_path="${2:-}"
  local process_ready="${3:-false}"
  local model_ready="${4:-false}"
  local model_status="${5:-unknown}"
  local readiness_source="${6:-not_configured}"
  local ready_json="${7:-}"
  python3 - "$STARTUP_STATUS_JSON" "$status" "$app_path" "$process_ready" "$model_ready" "$model_status" "$readiness_source" "$ready_json" <<'PY'
import json
import sys
path, status, app_path, process_ready, model_ready, model_status, readiness_source, ready_json = sys.argv[1:]
payload = {
    "status": status,
    "confirmed": status in {"pass", "ok", "green", "success"},
    "normalLaunch": True,
    "appPath": app_path,
    "processReady": process_ready.lower() == "true",
    "modelReady": model_ready.lower() == "true",
    "modelStatus": model_status,
    "readinessSource": readiness_source,
}
if ready_json:
    try:
        ready_payload = json.loads(ready_json)
        payload.update({
            "modelProfileID": ready_payload.get("modelProfileID") or ready_payload.get("modelProfile"),
            "promptMode": ready_payload.get("promptMode"),
            "modelPathExists": ready_payload.get("modelPathExists"),
            "fimTokensVerified": ready_payload.get("fimTokensVerified"),
            "configSource": ready_payload.get("configSource"),
        })
    except Exception as exc:
        payload["readinessParseError"] = str(exc)
open(path, "w", encoding="utf-8").write(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY
}

new_typeflow_pids() {
  local current
  current="$(pgrep -x "TypeFlow" 2>/dev/null || true)"
  while read -r pid; do
    [[ -z "$pid" ]] && continue
    if ! grep -qx "$pid" <<< "$TYPEFLOW_PIDS_BEFORE"; then
      echo "$pid"
    fi
  done <<< "$current"
}

model_ready_status() {
  if [[ -n "${TYPEFLOW_MODEL_READY_FILE:-}" && -f "${TYPEFLOW_MODEL_READY_FILE:-}" ]]; then
    python3 - "$TYPEFLOW_MODEL_READY_FILE" "$BENCHMARK_TYPEFLOW_PIDS" <<'PY'
import json
import sys
try:
    payload = json.load(open(sys.argv[1], encoding="utf-8"))
    
    file_pid = payload.get("pid")
    benchmark_pids = sys.argv[2].strip().split('\n') if len(sys.argv) > 2 else []
    
    is_pid_match = False
    if file_pid and str(file_pid) in benchmark_pids:
        is_pid_match = True
        
    if benchmark_pids and benchmark_pids[0] and not is_pid_match:
        print("false\tstale_readiness_pid_mismatch\tfile\t")
        sys.exit(0)
        
    profile = payload.get("modelProfileID") or payload.get("modelProfile")
    ready = (
        bool(payload.get("modelReady") or payload.get("ready"))
        and profile == "qwenCoderFIM"
        and payload.get("promptMode") == "fim"
        and bool(payload.get("modelPathExists"))
        and bool(payload.get("fimTokensVerified"))
    )
    status = payload.get("modelStatus") or ("ready" if ready else "not_ready")
    print(("true" if ready else "false") + "\t" + str(status) + "\tfile\t" + json.dumps(payload, sort_keys=True))
except Exception as exc:
    print("false\tinvalid_model_ready_file:" + str(exc) + "\tfile\t")
PY
  elif [[ -n "${TYPEFLOW_MODEL_READY_COMMAND:-}" ]]; then
    if bash -lc "$TYPEFLOW_MODEL_READY_COMMAND" >/dev/null 2>&1; then
      echo $'true\tready\tcommand\t'
    else
      echo $'false\tnot_ready\tcommand\t'
    fi
  else
    echo $'false\tunknown:not_configured\tnot_configured\t'
  fi
}

echo "Fixture SHA256 before run: $(hash_fixture)"

TEST_STATUS="unknown"
BUILD_STATUS="unknown"

if swift "$ROOT_DIR/devtools/tests/test_promptbuilder.swift" >"$TEST_LOG" 2>&1 && \
   swift "$ROOT_DIR/devtools/tests/test_overlap.swift" >>"$TEST_LOG" 2>&1 && \
   swift "$ROOT_DIR/devtools/tests/test_mem.swift" >>"$TEST_LOG" 2>&1; then
  TEST_STATUS="pass"
else
  TEST_STATUS="fail"
fi

if xcodebuild build -project "$PROJECT" -scheme "$SCHEME" -derivedDataPath "$DERIVED_DATA" >"$BUILD_LOG" 2>&1; then
  BUILD_STATUS="pass"
else
  BUILD_STATUS="fail"
fi

if [[ "$TEST_STATUS" == "pass" && "$BUILD_STATUS" == "pass" ]]; then
  write_build_status "pass" "$TEST_STATUS" "$BUILD_STATUS"
else
  write_build_status "fail" "$TEST_STATUS" "$BUILD_STATUS"
fi

APP_PATH="$(find "$DERIVED_DATA/Build/Products" -type d -name 'TypeFlow.app' -print -quit 2>/dev/null || true)"
if [[ -n "$APP_PATH" ]]; then
  echo "Launching TypeFlow normally from built app: $APP_PATH" | tee "$STARTUP_LOG"
  rm -f "$TYPEFLOW_MODEL_READY_FILE"
  open --env TYPEFLOW_DIAGNOSTICS_LOG="$DIAGNOSTICS_LOG" --stdout "$DIAGNOSTICS_LOG" --stderr "${DIAGNOSTICS_LOG}.err" -n "$APP_PATH"
  echo "Waiting up to 60s for model readiness file..."
  for i in {1..60}; do
    if [[ -f "${TYPEFLOW_MODEL_READY_FILE:-}" ]]; then
      echo "Readiness file found after ${i}s"
      break
    fi
    sleep 1
  done
  BENCHMARK_TYPEFLOW_PIDS="$(new_typeflow_pids)"
  if pgrep -x "TypeFlow" >/dev/null; then
    IFS=$'\t' read -r MODEL_READY MODEL_STATUS READINESS_SOURCE READY_JSON <<< "$(model_ready_status)"
    if [[ "$MODEL_READY" == "true" ]]; then
      write_startup_status "pass" "$APP_PATH" "true" "$MODEL_READY" "$MODEL_STATUS" "$READINESS_SOURCE" "$READY_JSON"
    else
      write_startup_status "config_fail" "$APP_PATH" "true" "$MODEL_READY" "$MODEL_STATUS" "$READINESS_SOURCE" "$READY_JSON"
    fi
  else
    write_startup_status "startup_fail" "$APP_PATH" "false" "false" "process_not_running" "process"
  fi
else
  echo "TypeFlow.app not found after build." | tee "$STARTUP_LOG"
  write_startup_status "startup_fail" "" "false" "false" "app_not_found" "build_products"
fi

echo "Fixture SHA256 at Safari benchmark start: $(hash_fixture)"

TYPEFLOW_DIAGNOSTICS_LOG="$DIAGNOSTICS_LOG" \
TYPEFLOW_BUILD_STATUS_JSON="$BUILD_STATUS_JSON" \
TYPEFLOW_STARTUP_STATUS_JSON="$STARTUP_STATUS_JSON" \
python3 "$SCRIPT_DIR/safari_product_benchmark.py"

python3 "$SCRIPT_DIR/analyze_safari_product_benchmark.py" --results "$RESULTS_JSON" --report "$REPORT_MD"

echo "Fixture SHA256 after run: $(hash_fixture)"
echo "Results: $RESULTS_JSON"
echo "Report: $REPORT_MD"
