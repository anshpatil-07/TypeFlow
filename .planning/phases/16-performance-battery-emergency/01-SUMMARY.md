---
phase: "16"
plan: "01"
subsystem: "Core"
tags: ["performance", "battery", "memory"]
requires: []
provides: ["Decoupled Event Tap", "CoreAnimation UI", "Hybrid Inference", "MLX Memory Unloading"]
affects: ["AccessibilityMonitor", "OverlayWindowController", "CompletionManager", "LLMEngine"]
tech-stack.added: ["CATextLayer"]
key-files.modified:
  - "TypeFlow/Services/AccessibilityMonitor.swift"
  - "TypeFlow/UI/OverlayWindowController.swift"
  - "TypeFlow/Services/CompletionManager.swift"
  - "TypeFlow/Services/LLMEngine.swift"
key-decisions:
  - "Offload AX caret and buffer tracking to a high-priority background queue (`com.cotyper.eventProcessing`) instead of main thread"
  - "Use CATextLayer wrapped in NSView for 60fps ghost text, falling back to NSHostingView only for Smart Reply/Rewrite states"
  - "Add 300ms threshold gate and short-word spellchecker heuristic to prevent unneeded MLX generation"
  - "Unload MLX context and nil the `modelContainer` after 5 minutes of inactivity"
requirements-completed: []
---

# Phase 16 Plan 01: Performance & Battery Emergency Summary

Overhauled the event tap and UI rendering pipeline to eliminate main-thread stutter, implemented a 300ms hybrid inference threshold to save battery, and added an inactivity timer to unload the MLX LLM after 5 minutes.

## Work Completed

- **Tasks Completed:** 4
- **Files Modified:** 4
- **Duration:** 20 min

## Key Changes

1.  **Main-Thread Decoupling:** Moved heavy `getCurrentCaretRect()` and string processing off `DispatchQueue.main` and onto a dedicated `userInteractive` queue in `AccessibilityMonitor`, preventing UI lockups during fast typing.
2.  **CoreAnimation UI:** Rewrote the ghost text overlay to use `OverlayContentView` backed by a `CATextLayer`. Swift UI's `NSHostingView` is now only spun up when interactive modes (Rewrite, Smart Reply) or loading indicators are active.
3.  **Hybrid Inference:** Extended the debounce timer to 300ms and added a stop-word/length heuristic in `CompletionManager` to bypass the MLX engine for trivial sequences (e.g., typing "the " or short `<10` character prefixes when standard spellchecker completions are available).
4.  **Memory Management:** Implemented an `inactivityTimer` in `LLMEngine` that completely unloads the model container and invalidates the KV cache if no generations occur for 300 seconds.

## Issues Encountered

None.

## Deviations from Plan

None - plan executed exactly as written.

## Self-Check

- [x] UI updates smoothly
- [x] `CATextLayer` text sizing matches previous look
- [x] Timer correctly invalidates after 5m

## Next Phase Readiness

Phase complete, ready for next step.
