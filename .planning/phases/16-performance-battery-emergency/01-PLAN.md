---
wave: 1
depends_on: []
files_modified:
  - TypeFlow/Services/AccessibilityMonitor.swift
  - TypeFlow/Services/CompletionManager.swift
  - TypeFlow/UI/OverlayWindowController.swift
  - TypeFlow/Services/LLMEngine.swift
---

# Phase 16: Performance & Battery Emergency Plan

<objective>
Overhaul the event tap and UI rendering pipeline to eliminate main-thread stutter, implement a 300ms hybrid inference threshold to save battery, and unload the MLX LLM after 5 minutes of inactivity.
</objective>

<task>
  <read_first>
    - TypeFlow/Services/AccessibilityMonitor.swift
  </read_first>
  <action>
    Modify the `CGEvent.tapCreate` callback in `AccessibilityMonitor.swift` to decouple it from the main thread.
    1. The callback must return `Unmanaged.passRetained(event)` immediately after returning `nil` for consumed events, without waiting for buffer processing.
    2. Move the call to `obj.handleKeystroke(keyCode: keyCode, event: event)` and the subsequent buffer snapshot into a dedicated background serial queue `private let processingQueue = DispatchQueue(label: "com.cotyper.eventProcessing", qos: .userInteractive)`.
    3. Update `handleKeystroke` to ensure it only mutates `keystrokeBuffer` safely from within `processingQueue`.
  </action>
  <acceptance_criteria>
    - `AccessibilityMonitor.swift` contains `private let processingQueue = DispatchQueue`
    - `CGEvent.tapCreate` callback returns the event immediately for non-consumed keys.
    - `handleKeystroke` and `onTextChanged` calls are wrapped in `processingQueue.async { ... }`
  </acceptance_criteria>
</task>

<task>
  <read_first>
    - TypeFlow/UI/OverlayWindowController.swift
  </read_first>
  <action>
    Rewrite `OverlayWindowController` to eliminate `NSHostingView` for standard ghost text rendering, using `CATextLayer` directly to save CPU.
    1. Create a custom `NSView` subclass named `OverlayContentView`. Give it a `layer` and set `wantsLayer = true`.
    2. Add a `CATextLayer` to `OverlayContentView` for rendering standard ghost text. Configure it with the system font (13pt) and disable implicit animations (`CATransaction.setDisableActions(true)`).
    3. Modify `OverlayWindowController.init` to use `OverlayContentView` as the window's `contentView` instead of `NSHostingView`.
    4. When `updateText` is called with `isRewrite == false` and `isSmartReply == false`, update the `CATextLayer` string directly.
    5. Retain SwiftUI ONLY for `RewriteModeBarView` and `SmartReplyOptionsView`. When those are needed, dynamically add an `NSHostingView` child to `OverlayContentView` and remove it when done.
  </action>
  <acceptance_criteria>
    - `OverlayWindowController.swift` contains `class OverlayContentView: NSView`
    - `OverlayContentView` uses `CATextLayer` for standard text.
    - `OverlayWindowController.init` sets `overlayWindow.contentView = OverlayContentView()`
  </acceptance_criteria>
</task>

<task>
  <read_first>
    - TypeFlow/Services/CompletionManager.swift
  </read_first>
  <action>
    Implement a Hybrid Inference Engine threshold gate in `CompletionManager.swift`.
    1. Change the strict 250ms debounce timer in `onTextChanged` to a 300ms timer (`debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.30, ...)`).
    2. Inside the timer callback before calling `triggerGeneration()`, check if the `activeLine` ends with common short stop-words (e.g., "the", "and", "is", "a", "to", "in"). If so, rely purely on `NSSpellChecker` inline completions and SKIP calling `LLMEngine`.
    3. If `activeLine.count < 10` and no `NSSpellChecker` suggestions exist, skip MLX generation to save battery on very short contexts.
  </action>
  <acceptance_criteria>
    - `CompletionManager.swift` contains `Timer.scheduledTimer(withTimeInterval: 0.30`
    - `triggerGeneration` (or the timer callback) contains a check against a set of stop-words or line length before invoking `LLMEngine.shared.generateCompletion`.
  </acceptance_criteria>
</task>

<task>
  <read_first>
    - TypeFlow/Services/LLMEngine.swift
  </read_first>
  <action>
    Implement an inactivity memory manager in `LLMEngine.swift` to unload the 1.5GB model.
    1. Add a `private var inactivityTimer: Timer?` property to `LLMEngine`.
    2. Create a method `resetInactivityTimer()` that invalidates the existing timer and schedules a new one for 300 seconds (5 minutes).
    3. Call `resetInactivityTimer()` inside `generateCompletion`, `generateRewrite`, and `generateSmartReplies`.
    4. When the timer fires, execute `modelContainer = nil` and `invalidateKVCache()`, and print `[TypeFlow-Debug] LLMEngine: Model unloaded due to 5 minutes of inactivity`.
  </action>
  <acceptance_criteria>
    - `LLMEngine.swift` contains `private var inactivityTimer: Timer?`
    - `LLMEngine.swift` contains `modelContainer = nil` inside the timer firing logic.
    - Timer duration is set to 300 seconds.
  </acceptance_criteria>
</task>

<must_haves>
- Event tap runs synchronously only for consumption, deferring processing to async queues.
- Ghost text renders using CATextLayer.
- MLX model is unloaded when idle for 5 minutes.
</must_haves>
