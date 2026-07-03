#!/usr/bin/env bash
# run_screen_context_benchmark.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
ARTIFACT_DIR="$ROOT_DIR/devtools/reports/benchmark_artifacts/screen_context"
DIAGNOSTICS_LOG="$ARTIFACT_DIR/typeflow_diagnostics.log"
TYPEFLOW_MODEL_READY_FILE="$HOME/Library/Application Support/TypeFlow/model_ready.json"
DERIVED_DATA="$ROOT_DIR/.build_derived_data"
SCHEME="TypeFlow"
PROJECT="$ROOT_DIR/TypeFlow.xcodeproj"

# Ensure we are not in TQB testing mode (which bypasses physical AX/OCR)
rm -f /tmp/typeflow_tqb_active

# Clean up artifact files from previous run, keeping DerivedData cache
if [[ -d "$ARTIFACT_DIR" ]]; then
  find "$ARTIFACT_DIR" -maxdepth 1 -not -name "DerivedData" -not -path "$ARTIFACT_DIR" -exec rm -rf {} +
else
  mkdir -p "$ARTIFACT_DIR"
fi

TYPEFLOW_PIDS_BEFORE="$(pgrep -x "TypeFlow" 2>/dev/null || true)"
BENCHMARK_TYPEFLOW_PIDS=""

cleanup() {
  if [[ -n "$BENCHMARK_TYPEFLOW_PIDS" ]]; then
    while read -r pid; do
      [[ -z "$pid" ]] && continue
      kill "$pid" 2>/dev/null || true
    done <<< "$BENCHMARK_TYPEFLOW_PIDS"
  fi
}
trap cleanup EXIT INT TERM

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

echo "Building TypeFlow..."
xcodebuild build -project "$PROJECT" -scheme "$SCHEME" -derivedDataPath "$DERIVED_DATA" > "$ARTIFACT_DIR/build.log" 2>&1

APP_PATH="$(find "$DERIVED_DATA/Build/Products" -type d -name 'TypeFlow.app' -print -quit 2>/dev/null || true)"
if [[ -z "$APP_PATH" ]]; then
  echo "Build failed or app not found!"
  exit 1
fi

echo "Launching TypeFlow..."
rm -f "$TYPEFLOW_MODEL_READY_FILE"
open --env TYPEFLOW_DIAGNOSTICS_LOG="$DIAGNOSTICS_LOG" --stdout "$DIAGNOSTICS_LOG" --stderr "${DIAGNOSTICS_LOG}.err" -n "$APP_PATH"

echo "Waiting for model readiness..."
for i in {1..60}; do
  if [[ -f "$TYPEFLOW_MODEL_READY_FILE" ]]; then
    break
  fi
  sleep 1
done

BENCHMARK_TYPEFLOW_PIDS="$(new_typeflow_pids)"

echo "Running Python screen context benchmark..."
TYPEFLOW_DIAGNOSTICS_LOG="$DIAGNOSTICS_LOG" python3 "$SCRIPT_DIR/screen_context_benchmark.py"

echo "Done."
