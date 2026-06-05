---
phase: "16"
plan: "02"
subsystem: "Core"
tags: ["performance", "debounce", "latency"]
requires: []
provides: ["AXUIElement Throttling", "Spacebar Fast-Path"]
affects: ["AccessibilityMonitor"]
tech-stack.added: []
key-files.modified:
  - "TypeFlow/Services/AccessibilityMonitor.swift"
key-decisions:
  - "Downgrade processingQueue QOS to `.utility` to avoid competing with the live typing thread on performance cores."
  - "Throttle AXUIElement context fetching with a 150ms debounce (`DispatchWorkItem`), unless the user types a word boundary (space, return, punctuation) which triggers an immediate fetch."
  - "Implement a fast-path for Spacebar and Return that immediately returns the event without routing the keystroke handling through the background queue."
requirements-completed: []
---

# Phase 16 Plan 02: Gap Closure - Typing Performance Summary

Implemented fixes for micro-stutters and dropped spacebar events discovered during Phase 16 UAT.

## Work Completed

- **Tasks Completed:** 3
- **Files Modified:** 1
- **Duration:** 10 min

## Key Changes

1. **Background QOS Downgrade**: Shifted `processingQueue` to `.utility` QOS to run on efficiency cores, freeing up performance cores for the main UI thread.
2. **Context Fetch Throttling**: Heavy AXUIElement queries (`getCurrentCaretRect`) and `CompletionManager` updates are now debounced by 150ms during continuous typing, preventing WindowServer floods.
3. **Spacebar/Return Fast-Path**: Key events that signal word boundaries immediately trigger a context fetch (0ms delay) but do so without blocking the instant passthrough of the keystroke event to the OS.

## Issues Encountered

None.

## Deviations from Plan

None - executed exactly as planned.

## Self-Check

- [x] Context fetching is debounced correctly.
- [x] Spacebar/Return events fast-path.
- [x] Background queue QOS changed.

## Next Phase Readiness

Phase fixes complete, ready for verification.
