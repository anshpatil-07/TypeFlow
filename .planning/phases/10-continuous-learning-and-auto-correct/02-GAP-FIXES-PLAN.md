---
wave: 1
depends_on: []
files_modified:
  - TypeFlow/Services/TypingHistoryManager.swift
  - TypeFlow/Services/CompletionManager.swift
  - TypeFlow/Services/VocabularyExtractor.swift
  - TypeFlow/Services/PromptBuilder.swift
  - TypeFlow/Services/AccessibilityMonitor.swift
autonomous: true
---

# Phase 10, Plan 2: Personalization Gap Fixes

<objective>
Fix gaps in typing history logging and prompt injection:
1. Add comprehensive console print logging to TypingHistoryManager, VocabularyExtractor, and PromptBuilder to make operations fully transparent.
2. Log corrected sentences on Tab-accepted spelling corrections and delimiter auto-corrections.
3. Log sentences when Return is pressed before the keystroke buffer is cleared.
4. Dynamically update custom vocabulary whenever a new sentence is logged so it is never stale or empty when personalization is enabled.
</objective>

<requirements>
- TBD
</requirements>

<tasks>
<task>
  <description>Add debug print logging and dynamic vocabulary updates</description>
  <read_first>
    - TypeFlow/Services/TypingHistoryManager.swift
    - TypeFlow/Services/VocabularyExtractor.swift
    - TypeFlow/Services/PromptBuilder.swift
  </read_first>
  <action>
    1. In `TypeFlow/Services/TypingHistoryManager.swift`:
       - Add print logs in `init()` showing Keychain key retrieval status and decrypted history item count.
       - Add print logs in `logSentence()` showing when a sentence is logged, skipped due to personalization being disabled, or skipped as a duplicate.
       - Add print logs in `saveHistory()` and `loadHistory()` to output success or error details.
       - Trigger `VocabularyExtractor.shared.extractVocabulary()` inside `logSentence()` after `saveHistory()` to keep custom vocabulary fresh.
    2. In `TypeFlow/Services/VocabularyExtractor.swift`:
       - Add print logs in `extractVocabulary()` showing the number of history items parsed and the top 15 words extracted.
       - Remove the `guard SettingsManager.shared.personalizationEnabled` check from `extractVocabulary()` so it can compute vocabulary from already-saved history whenever called, or ensure it correctly logs when skipped.
    3. In `TypeFlow/Services/PromptBuilder.swift`:
       - Add print logs in `buildPrompt()` showing whether personalization is enabled, the count of relevant writing samples matched/injected, and the specific vocabulary words prepended to the prompt.
  </action>
  <acceptance_criteria>
    - `TypingHistoryManager.swift` contains print statements for logging, saving, and loading history.
    - `VocabularyExtractor.swift` contains print statements showing active vocabulary extraction results.
    - `PromptBuilder.swift` contains print statements detailing personalization prompt injection statistics.
  </acceptance_criteria>
</task>

<task>
  <description>Fix sentence logging gates in CompletionManager and AccessibilityMonitor</description>
  <read_first>
    - TypeFlow/Services/CompletionManager.swift
    - TypeFlow/Services/AccessibilityMonitor.swift
  </read_first>
  <action>
    1. In `TypeFlow/Services/CompletionManager.swift`:
       - In `handleTabPressed()`, inside the `spellCorrection` block, log the corrected sentence to history using `TypingHistoryManager.shared.logSentenceFromText(correctedLine)` after constructing the corrected line.
       - In `onTextChanged()`, inside the `autoCorrectEnabled` check, construct the corrected sentence line (prior line prefix + corrected word + delimiter) and log it using `TypingHistoryManager.shared.logSentenceFromText(correctedLine)`.
    2. In `TypeFlow/Services/AccessibilityMonitor.swift`:
       - In `handleKeystroke()`, check if `keyCode == 36` (Return). If Return is pressed, log the current `keystrokeBuffer` to history using `TypingHistoryManager.shared.logSentenceFromText(keystrokeBuffer)` BEFORE calling `clearKeystrokeBuffer()`.
  </action>
  <acceptance_criteria>
    - `CompletionManager.swift` logs the corrected sentence when a spelling correction is accepted via Tab.
    - `CompletionManager.swift` logs the corrected sentence when delimiter-based auto-correction executes.
    - `AccessibilityMonitor.swift` logs the keystroke buffer to history before clearing it on Return key press.
  </acceptance_criteria>
</task>
</tasks>

<verification>
- Verify that typing sentences ending in a period or pressing Return prints console logs from TypingHistoryManager.
- Verify that accepting Tab spelling corrections and delimiter auto-corrections prints logs and records the corrected sentence.
- Verify that PromptBuilder outputs logs showing the exact number of prepended writing samples and custom vocabulary words.
</verification>

<must_haves>
- Completed sentences (ended by punctuation or Return) must be logged.
- Auto-corrected and Tab-accepted corrections must be logged in their corrected form.
- PromptBuilder must output logs indicating the status and size of injected personalization context.
</must_haves>
