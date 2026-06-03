---
status: diagnosed
phase: 10-continuous-learning-and-auto-correct
source:
  - 01-PERSONALIZATION-AUTO-CORRECT-SUMMARY.md
started: 2026-06-03T12:23:25+05:30
updated: 2026-06-03T12:47:44+05:30
---

## Current Test

[testing complete]

## Tests

### 1. Auto-correct Settings Toggle
expected: Open Settings UI, check if the toggle "Auto-correct misspelled words as you type" is visible in the General tab and successfully binds to/persists in SettingsManager.
result: pass

### 2. Delimiter Auto-Correction
expected: Type a misspelled word (e.g., "teh") followed by a delimiter (Space, period, comma, !, ?). The word is automatically replaced inline with its spell-corrected equivalent ("the") and the delimiter is appended.
result: pass

### 3. Personalization Settings Toggle & Consent
expected: Enable the personalization/long-term history logging toggle in Settings. Verify that typing complete sentences (ending in ., ?, or !) logs them. Disable it, type sentences, and verify they are NOT logged.
result: issue
reported: "fail — The auto-correct is working perfectly (logs show \"Automatically correcting 'stlye' to 'style'\"), but the history logging is completely broken. Typing complete sentences ending in a period (e.g. \"this is a test.\") does NOT trigger any history logging. There are no logs from TypingHistoryManager saving the sentence. Fix the event interception in CompletionManager or TextInjector so that naturally completed sentences (punctuation) and Tab-accepted completions are actually sent to the history manager to be saved."
severity: major

### 4. Secure Local History Storage
expected: History is stored locally in Application Support at TypeFlow/history.enc, encrypted using AES.GCM from CryptoKit with a 256-bit symmetric key retrieved securely from macOS Keychain.
result: issue
reported: "fail — The auto-correct is working perfectly, but the history logging is completely broken. Typing complete sentences ending in a period (e.g. \"this is a test.\") does NOT trigger any history logging. There are no logs from TypingHistoryManager saving the sentence. Fix the event interception in CompletionManager or TextInjector so that naturally completed sentences (punctuation) and Tab-accepted completions are actually sent to the history manager to be saved."
severity: major

### 5. Custom Vocabulary & Few-Shot Injection
expected: Top 15 custom vocabulary words (excluding stop words) are extracted in the background, and relevant past typing samples and custom vocabulary are prepended to the prompt by PromptBuilder.
result: issue
reported: "fail — The auto-correct works, but the Personalization/Continuous Learning system is non-functional. History is not being logged: Typing a full sentence ending in a period does not trigger any logs from TypingHistoryManager. The sentences are not being saved to the encrypted store. Prompt Injection is missing: The LLMEngine: Input prompt: logs show that the prompt is being sent without the [Past user writing samples] or [User vocabulary & jargon] blocks."
severity: major

### 6. Mid-word Spell Check Filtering
expected: If typing a word that is a prefix of a valid word (e.g., "were suppo..."), spell checker prefix guessing does not trigger, allowing LLM completion to take over.
result: pass

## Summary

total: 6
passed: 3
issues: 3
pending: 0
skipped: 0
blocked: 0

## Gaps

- truth: "Enable the personalization/long-term history logging toggle in Settings. Verify that typing complete sentences (ending in ., ?, or !) logs them. Disable it, type sentences, and verify they are NOT logged."
  status: failed
  reason: "User reported: fail — The auto-correct is working perfectly (logs show \"Automatically correcting 'stlye' to 'style'\"), but the history logging is completely broken. Typing complete sentences ending in a period (e.g. \"this is a test.\") does NOT trigger any history logging. There are no logs from TypingHistoryManager saving the sentence. Fix the event interception in CompletionManager or TextInjector so that naturally completed sentences (punctuation) and Tab-accepted completions are actually sent to the history manager to be saved."
  severity: major
  test: 3
  root_cause: "1. Lack of console logs in TypingHistoryManager made history logging invisible. 2. Auto-corrected sentences and Tab-accepted spelling corrections are not logged to history. 3. Pressing Return clears the keystroke buffer before onTextChanged runs, preventing the completed sentence from being logged."
  artifacts:
    - path: "TypeFlow/Services/TypingHistoryManager.swift"
      issue: "No console print statements to verify history operations."
    - path: "TypeFlow/Services/CompletionManager.swift"
      issue: "Tab-accepted spelling corrections and auto-corrections bypass history logging."
    - path: "TypeFlow/Services/AccessibilityMonitor.swift"
      issue: "Return key clears keystroke buffer before onTextChanged retrieves text."
  missing:
    - "Add print logs in TypingHistoryManager when logging, saving, or loading history."
    - "Log auto-corrected sentences and Tab-accepted spelling corrections to history."
    - "Log the sentence before Return clears the keystroke buffer."
  debug_session: ""

- truth: "History is stored locally in Application Support at TypeFlow/history.enc, encrypted using AES.GCM from CryptoKit with a 256-bit symmetric key retrieved securely from macOS Keychain."
  status: failed
  reason: "User reported: fail — The auto-correct is working perfectly, but the history logging is completely broken. Typing complete sentences ending in a period (e.g. \"this is a test.\") does NOT trigger any history logging. There are no logs from TypingHistoryManager saving the sentence. Fix the event interception in CompletionManager or TextInjector so that naturally completed sentences (punctuation) and Tab-accepted completions are actually sent to the history manager to be saved."
  severity: major
  root_cause: "History is encrypted and saved to disk correctly, but the lack of console logging or status verification made the feature's status completely opaque to the user."
  artifacts:
    - path: "TypeFlow/Services/TypingHistoryManager.swift"
      issue: "No console confirmation for successful keychain operations, encryption, or decryption."
  missing:
    - "Add debug logs to confirm Keychain key retrieval and AES.GCM encryption/decryption success."
  debug_session: ""

- truth: "Top 15 custom vocabulary words (excluding stop words) are extracted in the background, and relevant past typing samples and custom vocabulary are prepended to the prompt by PromptBuilder."
  status: failed
  reason: "User reported: fail — The auto-correct works, but the Personalization/Continuous Learning system is non-functional. History is not being logged: Typing a full sentence ending in a period does not trigger any logs from TypingHistoryManager. The sentences are not being saved to the encrypted store. Prompt Injection is missing: The LLMEngine: Input prompt: logs show that the prompt is being sent without the [Past user writing samples] or [User vocabulary & jargon] blocks."
  severity: major
  root_cause: "1. VocabularyExtractor runs only on launch, returning early if personalization is disabled at launch. If toggled on mid-session, vocabulary remains empty. 2. PromptBuilder has no debug logs to output active state of personalization/injection."
  artifacts:
    - path: "TypeFlow/Services/VocabularyExtractor.swift"
      issue: "Vocabulary extraction does not rerun when personalization is enabled mid-session or when sentences are added."
    - path: "TypeFlow/Services/PromptBuilder.swift"
      issue: "No console logs showing whether personalization blocks are prepended."
  missing:
    - "Trigger vocabulary extraction dynamically when personalization is enabled or updated."
    - "Add debug logs to PromptBuilder showing prepended samples count, vocabulary words count, and active personalization status."
  debug_session: ""
