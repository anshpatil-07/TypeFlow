---
phase: 18
wave: 1
depends_on: []
files_modified:
  - TypeFlow/Services/CompletionManager.swift
  - TypeFlow/Services/PromptBuilder.swift
  - TypeFlow/Services/AccessibilityMonitor.swift
requirements: []
autonomous: true
---

# Phase 18: Adaptive Intelligence

<objective>
Implement adaptive learning behaviors: 2-miss backoff, dynamic custom lexicon from backspace monitoring, prioritize document context over vocabulary, and semantic typo correction respecting the custom lexicon.
</objective>

<verification>
## Verification Criteria
- `CompletionManager.swift` contains logic to track ignored suggestions and suspend triggers for 10 seconds after 2 misses.
- `AccessibilityMonitor.swift` contains logic to detect backspacing over autocorrects and saving the new string to `UserDefaults.standard.stringArray(forKey: "UserCustomLexicon")`.
- `PromptBuilder.swift` prioritizes `textBeforeCaret` over `UserCustomLexicon` and injects the custom lexicon into `NSSpellChecker`.
- System prompt instructs the model to silently correct typos but explicitly preserve custom lexicon words.
</verification>

<must_haves>
- Flow State Backoff suspends triggers for 10 seconds after 2 consecutive misses.
- Custom strings retyped after backspace are saved to `UserCustomLexicon` in UserDefaults.
- Custom lexicon is injected into `NSSpellChecker` and `PromptBuilder`.
- MLX engine silently corrects typos but does NOT modify custom lexicon words.
</must_haves>

<tasks>
<task>
<read_first>
- TypeFlow/Services/CompletionManager.swift
- TypeFlow/Services/AccessibilityMonitor.swift
</read_first>
<action>
1. In `CompletionManager`, add state variables: `consecutiveMisses = 0`, `backoffUntil: Date? = nil`.
2. Update the completion trigger logic: if `backoffUntil` is set and in the future, return early (suspend automatic completions).
3. Track rejection: If ghost text is displayed and the user types a new character instead of accepting (via Tab/Right Arrow), increment `consecutiveMisses`. If accepted, reset `consecutiveMisses = 0`.
4. If `consecutiveMisses >= 2`, set `backoffUntil = Date().addingTimeInterval(10)` and reset `consecutiveMisses = 0`.
5. In `AccessibilityMonitor`, listen for backspace events (`deleteBackward`). Track when a user deletes recently completed text and manually types a new string. Save this custom string to `UserDefaults.standard.stringArray(forKey: "UserCustomLexicon")`.
</action>
<acceptance_criteria>
- `TypeFlow/Services/CompletionManager.swift` contains `var consecutiveMisses = 0` and `var backoffUntil: Date?`
- `CompletionManager.swift` contains `Date().addingTimeInterval(10)` to apply the 10-second flow state backoff.
- `TypeFlow/Services/AccessibilityMonitor.swift` handles backspace logic and interacts with `UserCustomLexicon` in `UserDefaults`.
</acceptance_criteria>
</task>

<task>
<read_first>
- TypeFlow/Services/PromptBuilder.swift
</read_first>
<action>
1. In `PromptBuilder`, retrieve `UserCustomLexicon` from UserDefaults.
2. Inject these custom words into Apple's `NSSpellChecker.shared.learnWord(_:)` so the system stops red-lining them.
3. Update `buildPrompt` logic: add instructions to strongly prioritize the document context (`textBeforeCaret`) over any custom vocabulary for predicting nouns. Explicitly state: "Prioritize the document context above. Vocabulary words are for stylistic tone, not strict content."
4. Add an instruction for semantic autocorrection: "Silently fix minor spelling errors based on surrounding context, but NEVER alter these exact user-specific words: [UserCustomLexicon string joined]".
</action>
<acceptance_criteria>
- `TypeFlow/Services/PromptBuilder.swift` contains `NSSpellChecker.shared.learnWord(_:)` for custom lexicon items.
- `TypeFlow/Services/PromptBuilder.swift` includes prompt text prioritizing document context over vocabulary.
- `TypeFlow/Services/PromptBuilder.swift` includes prompt text instructing semantic correction while protecting `UserCustomLexicon` words.
</acceptance_criteria>
</task>
</tasks>
