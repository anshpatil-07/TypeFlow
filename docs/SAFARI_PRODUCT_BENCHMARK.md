# Safari Product Benchmark

This benchmark validates TypeFlow's real Safari inline ghost-text behavior at pause checkpoints. It is a product benchmark, not a log-only benchmark: a run must prove that a Safari user would see ghost text, that Tab accepts only the visible ghost text, that empty completions fail, and that latency stays within the case threshold.

The benchmark is Safari-only. It uses generated local HTML pages or local file URLs from the fixture, never Safari Start Page or random websites.

## Files

- `tests/fixtures/safari_product_benchmark_cases.json`: immutable benchmark case fixture.
- `tests/fixtures/safari_benchmark_schema.json`: schema for fixture shape and locked defaults.
- `safari_product_benchmark.py`: Safari automation runner.
- `run_safari_product_benchmark.sh`: future one-command entrypoint.
- `analyze_safari_product_benchmark.py`: verdict analyzer.
- `benchmark_artifacts/`: generated pages, screenshots, logs, JSON results, and reports.

`benchmark_artifacts/` is ignored by git and should not be committed.

## How To Run

From the repo root:

```bash
bash run_safari_product_benchmark.sh
```

That command is intended for Antigravity or a human operator. It will run Swift tests, run CLI `xcodebuild`, launch TypeFlow normally from the built app, run the Safari benchmark, then run the analyzer.

Useful environment variables:

- `TYPEFLOW_XCODE_SCHEME`: defaults to `TypeFlow`.
- `TYPEFLOW_XCODE_PROJECT`: defaults to `TypeFlow.xcodeproj`.
- `TYPEFLOW_DIAGNOSTICS_LOG`: defaults to `benchmark_artifacts/typeflow_diagnostics.log`.
- `TYPEFLOW_XCODE_GUI_CONFIRMED=true`: records explicit Xcode GUI green confirmation when that has been checked.
- `TYPEFLOW_STARTUP_WAIT_SECONDS`: defaults to `5`.

## Fixture Immutability

At benchmark start, the runner computes the SHA256 of `tests/fixtures/safari_product_benchmark_cases.json` and stores it in `benchmark_results.json`.

At benchmark end, the runner recomputes the SHA256. If the hash changed, the analyzer returns `INVALID_BENCHMARK`.

The runner and analyzer must not write to the fixture file. Thresholds are locked: default runs per case is 1, the observation window is 300ms, default `maxLatencyMs` is 220ms, and the absolute hard ceiling is 250ms. The runner supports an optional repeat flag for future investigation, but the standard benchmark script uses the one-run default.

## What It Creates

Runtime files are written under `benchmark_artifacts/`:

- `pages/`: generated local Safari benchmark pages.
- `screenshots/`: one screenshot per case run after the observation window.
- `benchmark_results.json`: raw per-run results.
- `benchmark_report.md`: final report with every case and every run.
- `build_status.json`, `startup_status.json`, `xcodebuild_*.log`: build and startup evidence.

Screenshots are secondary evidence. Editor text, overlay state, visible ghost text, request correlation, and Tab insertion behavior are primary.

## Pause Checkpoints

The benchmark types the case prefix at a human-like cadence, records the timestamp of the final prefix character, stops typing, and observes for up to 300ms.

Continuous full-sentence typing is invalid for this benchmark because it can hide failures where suggestions only appear after the user has already moved on, or where stale suggestions survive behind new text. TypeFlow must show a current visible ghost at the pause checkpoint.

The 300ms observation window is not the pass threshold. A case passes latency only if visible ghost text appears within its `maxLatencyMs`, defaulting to 220ms. Any visible ghost after 250ms fails the hard ceiling.

## Verdicts

- `FINAL_PRODUCT_PASS`: fixture unchanged, build/startup confirmed green, every scheduled case run passes, context-aware cases pass, no empty completions, no invisible or stale Tab acceptance, p90 latency is at most 220ms, and max latency is at most 250ms except one clearly explained isolated non-repeating outlier.
- `PRODUCT_PASS_CONTEXT_AWARE_MISSING`: all scheduled non-context-aware runs pass, context-aware cases fail specifically because context-aware mode is missing or focused-editor-only, and latency/safety pass.
- `EMPTY_COMPLETION_FAIL`: any non-context-aware checkpoint has no visible ghost within the latency limit.
- `VISIBLE_GHOST_FAIL`: internal diagnostics claim a suggestion but the Safari user would not see usable ghost text, or the visible ghost violates content requirements.
- `TAB_ACCEPTANCE_FAIL`: Tab inserts invisible or stale ghost text, or inserted text differs from the visible ghost.
- `LATENCY_FAIL`: p90 `totalPauseToVisibleMs` exceeds 220ms, or max latency repeatedly exceeds 250ms.
- `BUILD_FAIL`: CLI build fails, Swift tests fail, Xcode GUI is known red, or build/startup green status is not confirmed.
- `INVALID_BENCHMARK`: fixture changed during the run, thresholds changed dynamically, failed cases were dropped, or result count does not equal fixture cases times configured repeat.
- `INCONCLUSIVE`: Safari automation fails or result-to-request correlation cannot be trusted.

## Context-Aware Failures

Context-aware cases require using visible page context, not only the focused editor prefix. For example, the GPU case must connect `RTX 4070 Super` with `12GB`, and the laptop case must include `24GB unified memory`.

If all non-context-aware cases pass and only these page-aware cases fail because the context source is `focusedEditorOnly` or equivalent, the analyzer can return `PRODUCT_PASS_CONTEXT_AWARE_MISSING`. That verdict is not a full product pass.

## Anti-Cheating Rules

- The fixture file is immutable during a run.
- Every case and every run appears in the final report.
- Repeated runs, when explicitly requested, must all pass; failures are not averaged away.
- Thresholds must not change dynamically.
- The app must not special-case benchmark IDs or fixture strings.
- Internal completion without visible ghost text fails.
- Tab is pressed only after visible ghost text exists, except safety tests that intentionally verify stale/invisible Tab behavior.
- Invisible or stale ghost text must never be accepted.
