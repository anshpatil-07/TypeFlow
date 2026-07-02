#!/bin/bash
for i in 1 2 3; do
    echo "======================================"
    echo "Running Repeatability Test $i"
    echo "======================================"
    ./run_fim_harness.sh
    cp stats_qwen_fim.txt "stats_repeat_$i.txt"
    cp typeflow_live.log "typeflow_live_$i.log"
    echo "Test $i completed."
    sleep 2
done
