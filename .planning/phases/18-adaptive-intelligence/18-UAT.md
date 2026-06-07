---
status: partial
phase: 18-adaptive-intelligence
source: [18-SUMMARY.md]
started: 2026-06-07T09:03:00Z
updated: 2026-06-07T09:03:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Flow State Backoff
expected: Type text to trigger an inline completion. Ignore it by typing another character instead of pressing Tab. Do this twice in a row. Stop typing. NO completion should trigger for at least 10 seconds.
result: issue
reported: "fail The app crashed during generation with a Fatal error: Index out of range. Crash Location: MLXArray+Indexing.swift at let size = ends[0] because ndim == 0 and the array is empty. The Issue: The logs show LLMEngine: Starting generate stream with suffix tokens count: 0.... LLMEngine is passing an empty suffixTokens array into the MLX generate function. MLX cannot process an empty tensor and crashes. The Fix: In LLMEngine.swift, inside generateCompletion, immediately after calculating suffixTokens, add a guard check: if suffixTokens.isEmpty { return \"\" }. Do not attempt to run MLXLMCommon.generate if there are 0 suffix tokens."
severity: blocker

### 2. Dynamic Lexicon
expected: Type a word. Press backspace to delete the entire word. Manually retype a different custom word and press space. Type the same custom word again; it should not be autocorrected or red-lined.
result: issue
reported: "fail The app crashed with the exact same Fatal error: Index out of range in MLXArray+Indexing.swift due to suffixTokens count: 0."
severity: blocker

### 3. Lexicon Protection
expected: Type sentences using the custom word you just saved. The AI completions should use context but preserve your custom word exactly as written.
result: issue
reported: "fail The app crashed with the exact same Fatal error: Index out of range in MLXArray+Indexing.swift due to suffixTokens count: 0."
severity: blocker

## Summary

total: 3
passed: 0
issues: 3
pending: 0
skipped: 0

## Gaps

- truth: "Type sentences using the custom word you just saved. The AI completions should use context but preserve your custom word exactly as written."
  status: failed
  reason: "User reported: fail The app crashed with the exact same Fatal error: Index out of range in MLXArray+Indexing.swift due to suffixTokens count: 0."
  severity: blocker
  test: 3
  artifacts: []
  missing: []

- truth: "Type a word. Press backspace to delete the entire word. Manually retype a different custom word and press space. Type the same custom word again; it should not be autocorrected or red-lined."
  status: failed
  reason: "User reported: fail The app crashed with the exact same Fatal error: Index out of range in MLXArray+Indexing.swift due to suffixTokens count: 0."
  severity: blocker
  test: 2
  artifacts: []
  missing: []

- truth: "Type text to trigger an inline completion. Ignore it by typing another character instead of pressing Tab. Do this twice in a row. Stop typing. NO completion should trigger for at least 10 seconds."
  status: failed
  reason: "User reported: fail The app crashed during generation with a Fatal error: Index out of range. Crash Location: MLXArray+Indexing.swift at let size = ends[0] because ndim == 0 and the array is empty. The Issue: The logs show LLMEngine: Starting generate stream with suffix tokens count: 0.... LLMEngine is passing an empty suffixTokens array into the MLX generate function. MLX cannot process an empty tensor and crashes. The Fix: In LLMEngine.swift, inside generateCompletion, immediately after calculating suffixTokens, add a guard check: if suffixTokens.isEmpty { return \"\" }. Do not attempt to run MLXLMCommon.generate if there are 0 suffix tokens."
  severity: blocker
  test: 1
  artifacts: []
  missing: []
