---
plan: 260608-bnr
phase: quick
status: pending
dependencies: []
---

# Quick Plan: Reorder AXTextMarker checks for WebKit caret tracking

## Objective
Fix the caret tracking bug in web browsers (Chrome, Safari, Zen) where the ghost text overlay appears at the bottom-left of the screen.

## Tasks

### 1. Reorder Caret Tracking Priority in AccessibilityMonitor
- **Files:** `TypeFlow/Services/AccessibilityMonitor.swift`
- **Action:** [MODIFY] Move the Chromium/WebKit specific AXTextMarker checks (`AXSelectedTextMarkerRange` and `AXSelectedTextMarker`) to the beginning of the `getCurrentCaretRect()` function, before the standard `kAXSelectedTextRangeAttribute` is checked.
- **Verify:** The logic correctly fetches browser-specific markers first, preventing browsers from incorrectly falling back to the entire web area bounds.
- **Done:** [ ]
