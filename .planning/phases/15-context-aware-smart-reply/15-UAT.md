---
status: complete
phase: 15-context-aware-smart-reply
source: [15-PLAN.md]
started: 2026-06-04T16:47:00Z
updated: 2026-06-04T16:47:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Trigger Smart Reply
expected: Focus a text field in an app (e.g., TextEdit). Press Cmd+Shift+R. TypeFlow should present an overlay saying "Generating options..." and then display exactly 3 short reply options in a popover.
result: issue
reported: "partial pass- only one of the options is visible as the overlay is display at the bottom left of the screen and i suspect the others are cutoff"
severity: major

### 2. UI Focus and Escape
expected: While the Smart Reply options are visible, TypeFlow should not steal the host application's focus (the text cursor should remain blinking). Pressing Escape should dismiss the popover immediately.
result: issue
reported: "partial pass- type flow doesn't steal the host application focus but pressing escape doesn't dismiss the popover"
severity: major

### 3. Accept Smart Reply
expected: Click one of the generated smart reply options. The popover should close, and the exact text of the chosen option should be injected into the host application at the cursor position.
result: pass

## Summary

total: 3
passed: 1
issues: 2
pending: 0
skipped: 0

## Gaps

- truth: "Focus a text field in an app (e.g., TextEdit). Press Cmd+Shift+R. TypeFlow should present an overlay saying \"Generating options...\" and then display exactly 3 short reply options in a popover."
  status: failed
  reason: "User reported: partial pass- only one of the options is visible as the overlay is display at the bottom left of the screen and i suspect the others are cutoff"
  severity: major
  test: 1
  artifacts: []
  missing:
    - Root Cause: OverlayWindowController does not account for screen bounds when repositioning. If the caret is near the bottom of the screen, flippedY pushes the window below the visible screen bounds, cutting off the options.
    - Fix: Add screen bounds checking in `repositionWindow()` to flip the popover above the caret if it would go off-screen.

- truth: "While the Smart Reply options are visible, TypeFlow should not steal the host application's focus (the text cursor should remain blinking). Pressing Escape should dismiss the popover immediately."
  status: failed
  reason: "User reported: partial pass- type flow doesn't steal the host application focus but pressing escape doesn't dismiss the popover"
  severity: major
  test: 2
  artifacts: []
  missing:
    - Root Cause: Escape key interception relies on `localEventMonitor` and `NSWindow.keyDown`, which only fire if TypeFlow is the active application. Since it's a non-activating panel, the global `CGEventTap` in `AccessibilityMonitor` must handle Escape.
    - Fix: Add `keyCode == 53` (Escape) interception in `AccessibilityMonitor.swift`'s `CGEventTap` handler to call `clearCompletion()` when `isSmartReply` or `isRewrite` is true.

