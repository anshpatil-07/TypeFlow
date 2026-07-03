---
wave: 1
depends_on: []
files_modified: ["TypeFlow/Services/SettingsManager.swift", "TypeFlow/UI/SettingsView.swift", "TypeFlow/Services/TypingHistoryManager.swift", "TypeFlow/Services/VocabularyExtractor.swift", "TypeFlow/Services/PromptBuilder.swift", "TypeFlow/Services/CompletionManager.swift", "project.yml"]
autonomous: true
---

# Phase 10, Plan 1: Personalization and Auto-Correct

<objective>
Implement typing history logging, local AES.GCM encryption of logs with Keychain key management, periodic background vocabulary extraction, prompt builder context injection, and delimiter-based auto-correction.
</objective>

<requirements>
- TBD
</requirements>

<tasks>
<task>
  <description>Create typing history manager, vocabulary extractor, and settings toggles</description>
  <read_first>
    - TypeFlow/Services/SettingsManager.swift
    - TypeFlow/UI/SettingsView.swift
  </read_first>
  <action>
    1. In `TypeFlow/Services/SettingsManager.swift`, add `@AppStorage("personalizationEnabled") var personalizationEnabled: Bool = false` and `@AppStorage("autoCorrectEnabled") var autoCorrectEnabled: Bool = false`.
    2. In `TypeFlow/UI/SettingsView.swift`, add Toggle controls in the General tab for both "Auto-correct misspelled words as you type" and "Enable personalization (Typing History)".
    3. Create `TypeFlow/Services/TypingHistoryManager.swift` which generates a 256-bit symmetric key, saves it to the Keychain, serializes sentence arrays, encrypts them via `AES.GCM`, and writes them to Application Support.
    4. Create `TypeFlow/Services/VocabularyExtractor.swift` to count frequencies of words >= 4 characters (excluding stopwords), selecting the top 15 words that appear at least twice, running asynchronously on launch and once every 24 hours.
  </action>
  <acceptance_criteria>
    - `SettingsManager.swift` contains `@AppStorage("personalizationEnabled")`
    - `SettingsView.swift` contains personalization and auto-correct Toggles
    - `TypingHistoryManager.swift` exists and contains Keychain and `AES.GCM.seal` encryption code
    - `VocabularyExtractor.swift` exists and contains stopword filtering and 24-hour Timer logic
  </acceptance_criteria>
</task>

<task>
  <description>Integrate history logging, prompt building context, and auto-correct logic</description>
  <read_first>
    - TypeFlow/Services/PromptBuilder.swift
    - TypeFlow/Services/CompletionManager.swift
  </read_first>
  <action>
    1. In `TypeFlow/Services/PromptBuilder.swift`, retrieve context matched writing samples and top 15 vocabulary keywords, prepending them as metadata blocks if personalization is enabled.
    2. In `TypeFlow/Services/CompletionManager.swift`, call `TypingHistoryManager.shared.logSentenceFromText(activeLine)` inside `onTextChanged()`.
    3. In `TypeFlow/Services/CompletionManager.swift`, call `TypingHistoryManager.shared.logSentence(activeLine + completion)` inside `handleTabPressed()` when accepting an LLM completion.
    4. In `TypeFlow/Services/CompletionManager.swift`, check if the last word is misspelled when user types a delimiter (Space, period, comma, !, ?). If auto-correct is enabled, automatically delete the misspelled word, inject the correction, and append the delimiter.
  </action>
  <acceptance_criteria>
    - `PromptBuilder.swift` prepends `[Past user writing samples]` and `[User vocabulary & jargon]`
    - `CompletionManager.swift` calls `logSentenceFromText` in `onTextChanged`
    - `CompletionManager.swift` calls `logSentence` on Tab completion acceptance
    - `CompletionManager.swift` contains delimiter auto-correct logic that deletes misspelled words and injects corrections
  </acceptance_criteria>
</task>
</tasks>

<verification>
- Verify that complete sentences and accepted tab completions are logged securely.
- Verify that matched writing samples and vocabulary are prepended to the prompt when personalization is enabled.
- Verify that spelling corrections are automatically injected on delimiter keystrokes when auto-correct is active.
</verification>

<must_haves>
- Personalization must be opt-in.
- History logs must be encrypted locally using AES.GCM.
- Delimiter keystrokes must trigger auto-correction when the toggle is enabled.
</must_haves>
