#!/bin/bash
# memory_plateau_benchmark.sh
# Samples TypeFlow RSS every 5s for 60s while stress-typing.
# Pass: final RSS within 50MB of warm RSS (no runaway growth).
# Fail: RSS grows more than 100MB over 60s baseline.

set -e

TYPEFLOW_PID=$(pgrep -x TypeFlow 2>/dev/null | head -1)
if [ -z "$TYPEFLOW_PID" ]; then
    echo "ERROR: TypeFlow not running. Launch the app first."
    exit 1
fi

echo "[MemoryBenchmark] TypeFlow PID=$TYPEFLOW_PID"
echo "[MemoryBenchmark] Sampling RSS every 5s for 60s..."

SAMPLES=()
START_RSS=0

get_rss_mb() {
    # ps rss is in KB on macOS
    local rss_kb
    rss_kb=$(ps -o rss= -p "$1" 2>/dev/null | tr -d ' ')
    if [ -z "$rss_kb" ]; then echo "0"; return; fi
    echo $(( rss_kb / 1024 ))
}

# Baseline sample before stress
START_RSS=$(get_rss_mb "$TYPEFLOW_PID")
SAMPLES+=("$START_RSS")
echo "[MemoryBenchmark] t=0s  RSS=${START_RSS}MB (baseline)"

# Start stress typing in the background (requires TextEdit or similar focused)
LONG_TEXT="The quick brown fox jumps over the lazy dog. Performance testing is important. Memory should plateau after warm up. TypeFlow must not leak objects. The model runs on device and is efficient. Writing helps test autocomplete quality. Proper async cleanup prevents memory growth. Swift actors help serialize access."
python3 stress_type.py --text "$LONG_TEXT$LONG_TEXT" --wpm 120 &
STRESS_PID=$!

for i in $(seq 5 5 60); do
    sleep 5
    RSS=$(get_rss_mb "$TYPEFLOW_PID")
    SAMPLES+=("$RSS")
    echo "[MemoryBenchmark] t=${i}s  RSS=${RSS}MB"
done

wait $STRESS_PID 2>/dev/null || true

WARM_RSS=${SAMPLES[3]}              # t=10s (index 3 in 1-indexed zsh) after model warm-up
FINAL_RSS=${SAMPLES[${#SAMPLES[@]}]} # last sample (t=60s), zsh-compatible
DELTA=$(( FINAL_RSS - WARM_RSS ))

echo ""
echo "[MemoryBenchmark] Summary:"
echo "  Baseline (t=0s):  ${START_RSS}MB"
echo "  Warm (t=10s):     ${WARM_RSS}MB"
echo "  Final (t=60s):    ${FINAL_RSS}MB"
echo "  Delta warm→final: +${DELTA}MB"

if [ "$DELTA" -le 50 ]; then
    echo "[MemoryBenchmark] PASS: RSS growth ≤50MB — memory is plateauing."
else
    echo "[MemoryBenchmark] FAIL: RSS grew ${DELTA}MB after warm-up — possible leak."
fi
