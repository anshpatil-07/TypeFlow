#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
ARTIFACT_DIR="$ROOT_DIR/devtools/reports/benchmark_artifacts/acceptance_behavior"
DIAGNOSTICS_LOG="$ARTIFACT_DIR/typeflow_diagnostics.log"
TYPEFLOW_MODEL_READY_FILE="$HOME/Library/Application Support/TypeFlow/model_ready.json"
DERIVED_DATA="$(mktemp -d "${TMPDIR:-/tmp}/typeflow-deriveddata.XXXXXX")"
SCHEME="TypeFlow"
PROJECT="$ROOT_DIR/TypeFlow.xcodeproj"

rm -rf "$ARTIFACT_DIR"
mkdir -p "$ARTIFACT_DIR"

TYPEFLOW_PIDS_BEFORE="$(pgrep -x "TypeFlow" 2>/dev/null || true)"
BENCHMARK_TYPEFLOW_PIDS=""

cleanup() {
  if [[ -n "$BENCHMARK_TYPEFLOW_PIDS" ]]; then
    while read -r pid; do
      [[ -z "$pid" ]] && continue
      kill "$pid" 2>/dev/null || true
    done <<< "$BENCHMARK_TYPEFLOW_PIDS"
  fi
  if [[ -n "${DERIVED_DATA:-}" && -d "$DERIVED_DATA" && "$DERIVED_DATA" != "/" && "$DERIVED_DATA" != "$HOME" && "$DERIVED_DATA" != "$ROOT_DIR" && "$DERIVED_DATA" == *"/typeflow-deriveddata."* ]]; then
    rm -rf "$DERIVED_DATA"
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

echo "Running Python acceptance behavior benchmark..."
TYPEFLOW_DIAGNOSTICS_LOG="$DIAGNOSTICS_LOG" python3 "$SCRIPT_DIR/acceptance_behavior_benchmark.py"

echo "Analyzing results..."
python3 "$SCRIPT_DIR/analyze_acceptance_behavior_benchmark.py"

echo "Done."
