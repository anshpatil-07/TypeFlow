---
phase: "16"
plan: "02"
type: "gap_closure"
objective: "Fix typing performance micro-stutters and dropped spacebar events by throttling AXUIElement fetches, bypassing background queue for space/return, and downgrading QOS to utility."
requirements: []
user_setup: []
---

# Phase 16: Gap Closure - Typing Performance Fixes

This plan implements fixes for gaps discovered during UAT Phase 16, specifically targeting micro-stutters during fast typing and dropped spacebar events.

## Gaps Addressed

1. **Typing Performance**: AXUIElement fetches are flooding the background queue on every keystroke. Spacebar events are delayed. Background queue QOS is too high (`userInteractive`), competing with the live typing thread on performance cores.

## Proposed Changes

### `TypeFlow/Services/AccessibilityMonitor.swift`

#### 1. Downgrade Background QOS

- Change `processingQueue` QOS from `.userInteractive` to `.utility` to shift heavy processing to efficiency cores.

#### 2. Throttle Context Fetching

- Add a debounce mechanism (e.g. `DispatchWorkItem`) for `getCurrentCaretRect()` and `CompletionManager.shared.onTextChanged()`.
- Only trigger the AXUIElement context refresh immediately if the keystroke is a spacebar, return, or punctuation.
- Otherwise, debounce the fetch by 150ms. If the user keeps typing fast, it won't flood the window server.

#### 3. Spacebar / Return Fast-Path

- In `tapCreate`, if `keyCode == 49` (Space) or `keyCode == 36` (Return), immediately update the internal keystroke buffer locally and `return Unmanaged.passRetained(event)` without ever touching the `processingQueue` for the keystroke itself.
- Trigger the throttled context fetch as normal, but don't hold up the event return for it.

## Verification Plan

### Manual Verification
1. Open a text editor and type continuously very fast. Verify there are no micro-stutters.
2. Type words with spaces ("type large") rapidly and verify the spacebar is never dropped.
3. Verify that ghost text still appears correctly when pausing for 150ms+.
