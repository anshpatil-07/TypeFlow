---
status: diagnosed
phase: 07-model-ui-downloads
source:
  - 01-SUMMARY.md
started: 2026-05-23T05:22:15Z
updated: 2026-05-23T05:22:15Z
---

## Current Test

[testing complete]

## Tests

### 1. Models Tab Visibility
expected: |
  Open the Settings window from the Menu Bar. There is a "Models" tab visible. Clicking it displays a list of available MLX models (e.g. Gemma 4 E2B and Qwen 2.5 1.5B).
result: issue
reported: "fail — there is no Models tab visible in the Settings window at all. The tab does not exist in the UI."
severity: major

### 2. Download Simulation
expected: |
  In the Models tab, click the "Download" button next to a model. A progress indicator should appear and gradually increase to 100% over a few seconds, eventually changing the model's status to downloaded.
result: blocked
blocked_by: prior-phase
reason: "fail — there is no Models tab visible in the Settings window at all. The tab does not exist in the UI."

### 3. Activate Model
expected: |
  Once a model is downloaded, an "Activate" button should appear next to it. Clicking "Activate" changes its state to "Active" (highlighted in green), indicating it is the currently selected model.
result: blocked
blocked_by: prior-phase
reason: "fail — there is no Models tab visible in the Settings window at all. The tab does not exist in the UI."

## Summary

total: 3
passed: 0
issues: 1
pending: 0
skipped: 2

## Gaps

- truth: "Open the Settings window from the Menu Bar. There is a \"Models\" tab visible. Clicking it displays a list of available MLX models (e.g. Gemma 4 E2B and Qwen 2.5 1.5B)."
  status: failed
  reason: "User reported: fail — there is no Models tab visible in the Settings window at all. The tab does not exist in the UI."
  severity: major
  test: 1
  root_cause: "Placing a `List` inside a `Form` in macOS SwiftUI causes the `List` to collapse to 0 height or fail to render entirely due to nested scroll views, making the entire Models tab blank/missing."
  artifacts:
    - path: "TypeFlow/UI/SettingsView.swift"
      issue: "`List` is nested inside `Form` which breaks the layout on macOS."
  missing:
    - "Remove `List` and use `ForEach` directly inside `Form` OR replace `Form` with a `List` for the entire tab."

