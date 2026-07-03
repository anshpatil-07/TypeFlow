# Phase 9: Completions Overhaul - Research

## Objective
Research how to implement Phase 9: Completions Overhaul. What do I need to know to PLAN this phase well?

## Context
Based on CONTEXT.md, we need to implement:
- **D-01:** Cancel in-flight LLM generation immediately on any new keystroke
- **D-02:** Use 150ms debounce
- **D-03:** SF Pro generic gray ghost text
- **D-04:** No animation
- **D-05:** Intercept Tab using CGEvent tap when ghost text is visible
- **D-06:** Pass Tab through if no ghost text is visible
- **D-07:** Silently ignore empty outputs
- **D-08:** Strip echoed prefix

## Findings & Codebase Context

1. **D-01 & D-02 (Lifecycle):** 
   - `CompletionManager.swift` (Lines 30-35) uses a 0.3s `debounceTimer`. We must update this to `0.15`.
   - The generation is dispatched via `Task { ... }` on Line 76. We must store this in a property `private var currentGenerationTask: Task<Void, Never>?` and call `currentGenerationTask?.cancel()` immediately inside `onTextChanged()` to abort in-flight MLX operations when the user keeps typing.
   - We must also ensure `LLMEngine.generateCompletion` respects `Task.isCancelled`.

2. **D-03 & D-04 (Styling):** 
   - `OverlayWindowController.swift` already implements `SF Pro` (`.font(.system(size: 13))`) and uses `Color.secondary` (gray). There are no animations. It currently satisfies the criteria.

3. **D-05 & D-06 (Tab Interception):** 
   - `AccessibilityMonitor.swift` (Lines 76-88) intercepts `Tab` via `CGEvent.tapCreate` and calls `CompletionManager.shared.handleTabPressed()`.
   - `CompletionManager.swift` (Line 94-102) returns `true` (consumes) if `currentCompletion` is available, and `false` (passes through) otherwise. This already correctly implements the requirements.

4. **D-07 & D-08 (Edge cases):**
   - **D-07:** In `CompletionManager.swift` (Line 82), we check `if !completion.isEmpty`. We should change this to `if !completion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty` so whitespace-only responses are silently ignored.
   - **D-08:** LLMs often echo the last few words of the input. We need a utility function to strip matching prefixes. E.g., if `activeLine` is "Hello world" and completion is "world! How are you?", we should strip "world" and just show "! How are you?". This logic should be placed right after the `LLMEngine` returns the text in `CompletionManager.swift`.

## Validation Architecture
- [ ] Typing rapidly does not launch multiple parallel MLX inferences (cancel works).
- [ ] Debounce feels extremely fast (150ms).
- [ ] Ghost text uses system font and does not animate.
- [ ] Tab inserts ghost text if visible.
- [ ] Tab acts normally if ghost text is not visible.
- [ ] Whitespace-only completions show no ghost text.
- [ ] Echoed prefixes (e.g., input "the quick", LLM outputs "the quick brown fox") are stripped down to just the continuation (" brown fox").

## RESEARCH COMPLETE
