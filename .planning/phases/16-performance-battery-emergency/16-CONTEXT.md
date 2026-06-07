# Phase 16: Performance & Battery Emergency - Context

**Gathered:** 2026-06-04
**Status:** Ready for planning

<domain>
## Phase Boundary

Performance and Battery Optimization: Resolving the typing stutter and battery drain caused by continuous CPU/Memory usage. Overhauling the event tap and inline rendering pipeline, creating a hybrid inference engine, and implementing MLX memory management.

</domain>

<decisions>
## Implementation Decisions

### Main-Thread Decoupling
- **D-01:** The CGEventTap callback MUST return the original CGEvent immediately (unless explicitly swallowing Tab/Escape).
- **D-02:** Move all buffer updates, tracking, and LLMEngine trigger logic completely off the Main Thread to a background queue (DispatchQueue.global(qos: .userInitiated)) or a background Actor.

### CoreAnimation Ghost UI
- **D-03:** Strip SwiftUI out of the inline Ghost Text overlay window.
- **D-04:** Rewrite the inline ghost text renderer using a raw AppKit NSWindow containing a single CALayer and CATextLayer to eliminate SwiftUI layout overhead.

### Hybrid Inference Engine
- **D-05:** Implement a Threshold Gate in `CompletionManager`. Use Apple's built-in `NSSpellChecker` for instant, 0-CPU predictions if the current word buffer is short or the user is typing common stop-words.
- **D-06:** Only spin up the MLX LLM model if the user pauses typing for >300ms.

### MLX Memory Management
- **D-07:** Implement an inactivity timer in `LLMEngine`. If no keystrokes are registered for 5 minutes, completely unload the model from memory. Re-load asynchronously when typing resumes.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### App Context
- `.planning/PROJECT.md` — Core value constraints, architecture constraints.
- `.planning/REQUIREMENTS.md` — Requirements and current milestone details.
- `TypeFlow/Services/AccessibilityMonitor.swift` — Current event tap implementation.
- `TypeFlow/Services/CompletionManager.swift` — Current trigger logic.
- `TypeFlow/UI/OverlayWindowController.swift` — Current SwiftUI ghost text overlay.

</canonical_refs>

<specifics>
## Specific Ideas
- The user explicitly mandated dropping SwiftUI for the ghost text overlay, relying entirely on `CALayer` and `CATextLayer` for 60fps tracking without CPU spikes.
</specifics>

<deferred>
## Deferred Ideas
None
</deferred>
