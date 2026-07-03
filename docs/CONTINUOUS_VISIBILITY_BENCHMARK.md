# Continuous Visibility Benchmark

## Purpose
This benchmark tests TypeFlow's ability to provide continuous, coherent, and fast ghost text suggestions while the user is typing, specifically focusing on the behavior during natural pauses (e.g., after typing every 2 words).

## Key Criteria
- **Visibility**: Ghost text should be visible after a typing pause.
- **Latency**: Ghost text should appear within a maximum of 250ms (target 220ms) from the end of the keystroke.
- **Quality (Heuristics)**:
  - Natural length: 2 to 6 words when context allows.
  - Non-repetitive: Should not repeat the last 3-8 typed words.
  - Coherent: Should not restart the sentence or contain markup/list markers.
- **Divergence**: If the user continues typing and diverges from the suggestion, the old ghost text MUST disappear immediately and must not be accept-ready.

## How to Run
```bash
bash run_continuous_visibility_benchmark.sh
```

## Reports
Results and HTML artifacts are saved to `benchmark_artifacts/continuous_visibility/`.
Check `benchmark_report.md` for a summary of pass/fail criteria and per-checkpoint latency and quality metrics.
