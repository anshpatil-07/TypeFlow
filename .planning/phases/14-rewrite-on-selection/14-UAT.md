---
status: testing
phase: 14-rewrite-on-selection
source: 14-SUMMARY.md
started: 2026-06-03T18:03:00Z
updated: 2026-06-03T18:03:00Z
---

## Current Test

number: 1
name: Custom Shortcut Settings
expected: |
  Open the Settings View and switch to the General tab. Confirm that a picker labeled 'Rewrite Shortcut:' exists and allows choosing between Option/Control and R/E/W combinations.
awaiting: user response

## Tests

### 1. Custom Shortcut Settings
expected: Open the Settings View and switch to the General tab. Confirm that a picker labeled 'Rewrite Shortcut:' exists and allows choosing between Option/Control and R/E/W combinations.
result: [pending]

### 2. Shortcut Interception
expected: In a text editor (e.g., TextEdit), type a sentence, select it, and press the configured rewrite shortcut (e.g., Option+R). Confirm that the keystroke is consumed by the app and does NOT output literal characters (like ®).
result: [pending]

### 3. Rewrite Loading Indicator
expected: After pressing the shortcut, verify the Caret Overlay displays next to the selection caret showing a spinner indicating 'Rewriting selection...'
result: [pending]

### 4. Rewrite Suggestion UI
expected: Verify that the LLM generates a rewrite suggestion, and the overlay updates to display the suggestion alongside a blue/teal gradient 'REWRITE' badge.
result: [pending]

### 5. Selection Replacement
expected: Press Tab. Confirm that the original selected text in TextEdit is deleted and replaced by the new rewritten suggestion.
result: [pending]

### 6. Cancel Suggestion
expected: Select a different word, press Option+R to show the rewrite overlay, then press Escape or start typing. Confirm that the overlay disappears immediately.
result: [pending]

## Summary

total: 6
passed: 0
issues: 0
pending: 6
skipped: 0

## Gaps

[none yet]
