---
wave: 1
depends_on: []
files_modified: ["TypeFlow/Services/CompletionManager.swift"]
autonomous: true
---

# Phase 9, Plan 1: Pipeline Overhaul

<objective>
Implement the completion lifecycle management and edge case handling to meet the <150ms performance target and avoid echo effects.
</objective>

<requirements>
- TBD
</requirements>

<tasks>
<task>
  <description>Update generation lifecycle with fast debounce and task cancellation</description>
  <read_first>
    - TypeFlow/Services/CompletionManager.swift
  </read_first>
  <action>
    1. In `TypeFlow/Services/CompletionManager.swift`, add a new property: `private var currentGenerationTask: Task<Void, Never>?`
    2. Inside `onTextChanged()`, immediately call `currentGenerationTask?.cancel()` at the beginning of the function (before clearing completion).
    3. Update the `debounceTimer` interval from `0.3` to `0.15`.
    4. Inside `triggerGeneration()`, when dispatching the LLM task, assign it to `currentGenerationTask = Task { ... }`.
  </action>
  <acceptance_criteria>
    - `TypeFlow/Services/CompletionManager.swift` contains `private var currentGenerationTask: Task<Void, Never>?`
    - `TypeFlow/Services/CompletionManager.swift` contains `currentGenerationTask?.cancel()` in `onTextChanged`
    - `debounceTimer` is initialized with `0.15`
  </acceptance_criteria>
</task>

<task>
  <description>Handle edge cases: empty outputs and echoed prefixes</description>
  <read_first>
    - TypeFlow/Services/CompletionManager.swift
  </read_first>
  <action>
    1. In `triggerGeneration()`, after `let completion = await LLMEngine.shared.generateCompletion(context: prompt)`, add logic to trim whitespace and strip echoed prefixes.
    2. Define a helper variable `var processedCompletion = completion.trimmingCharacters(in: .whitespacesAndNewlines)`.
    3. Strip prefix by finding the longest common suffix of `activeLine` and prefix of `processedCompletion`:
       ```swift
       var overlapLength = 0
       let maxOverlap = min(activeLine.count, processedCompletion.count)
       for i in (1...maxOverlap).reversed() {
           let suffix = activeLine.suffix(i)
           let prefix = processedCompletion.prefix(i)
           if suffix.lowercased() == prefix.lowercased() {
               overlapLength = i
               break
           }
       }
       if overlapLength > 0 {
           processedCompletion = String(processedCompletion.dropFirst(overlapLength))
       }
       ```
    4. Update the condition from `if !completion.isEmpty` to `if !processedCompletion.isEmpty`.
    5. Pass `processedCompletion` to `self.currentCompletion` and `self.overlayWindowController?.updateText(processedCompletion)`.
  </action>
  <acceptance_criteria>
    - `TypeFlow/Services/CompletionManager.swift` contains `trimmingCharacters(in: .whitespacesAndNewlines)`
    - Prefix stripping logic is present comparing `activeLine.suffix` and `processedCompletion.prefix`
    - `if !processedCompletion.isEmpty` replaces `if !completion.isEmpty`
  </acceptance_criteria>
</task>
</tasks>

<verification>
- Verify that typing rapidly resets the debounce and cancels tasks.
- Verify that typing "hello world" and model returning " world how are you" results in ghost text " how are you".
- Verify that whitespace outputs result in no ghost text shown.
</verification>

<must_haves>
- Debounce must be 0.15s.
- In-flight tasks must be cancelled.
- Echoed text must be stripped.
</must_haves>
