---
status: partial
phase: 18-adaptive-intelligence
source: [18-SUMMARY.md]
started: 2026-06-07T09:17:00Z
updated: 2026-06-07T09:17:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Flow State Backoff
expected: Type text to trigger an inline completion. Ignore it by typing another character instead of pressing Tab. Do this twice in a row. Stop typing. NO completion should trigger for at least 10 seconds.
result: pass

### 2. Dynamic Lexicon
expected: Type a word. Press backspace to delete the entire word. Manually retype a different custom word and press space. Type the same custom word again; it should not be autocorrected or red-lined.
result: pass

### 3. Lexicon Protection
expected: Type sentences using the custom word you just saved. The AI completions should use context but preserve your custom word exactly as written.
result: issue
reported: "fail The Dynamic Lexicon successfully protected the custom word, but the AI generation completely hallucinated due to prompt leakage. The Issue: The LLM ignored the document context and generated a literal comma-separated list of the injected vocabulary words. (Output: using, should, brown, working, typing...). The PromptBuilder system instructions are causing the 4B model to treat the vocabulary array as a list to be recited, rather than a passive stylistic influence. The Fix: Open PromptBuilder.swift. Radically soften how the vocabulary is presented to the model. Instead of listing them aggressively, wrap them in a much stricter context instruction. Add this exact negative constraint to the system prompt: \"CRITICAL: You are an invisible autocomplete engine. DO NOT recite, list, or explicitly mention the provided vocabulary words. Only use them naturally if they flawlessly fit the immediate grammatical context of the suffix. Prioritize the user's document context above all else.\" Ensure the system prompt clearly separates the System Instructions from the User Text so the model doesn't blend them together."
severity: blocker

## Summary

total: 3
passed: 2
issues: 1
pending: 0
skipped: 0

## Gaps

- truth: "Type sentences using the custom word you just saved. The AI completions should use context but preserve your custom word exactly as written."
  status: failed
  reason: "User reported: fail The Dynamic Lexicon successfully protected the custom word, but the AI generation completely hallucinated due to prompt leakage. The Issue: The LLM ignored the document context and generated a literal comma-separated list of the injected vocabulary words. (Output: using, should, brown, working, typing...). The PromptBuilder system instructions are causing the 4B model to treat the vocabulary array as a list to be recited, rather than a passive stylistic influence. The Fix: Open PromptBuilder.swift. Radically soften how the vocabulary is presented to the model. Instead of listing them aggressively, wrap them in a much stricter context instruction. Add this exact negative constraint to the system prompt: \"CRITICAL: You are an invisible autocomplete engine. DO NOT recite, list, or explicitly mention the provided vocabulary words. Only use them naturally if they flawlessly fit the immediate grammatical context of the suffix. Prioritize the user's document context above all else.\" Ensure the system prompt clearly separates the System Instructions from the User Text so the model doesn't blend them together."
  severity: blocker
  test: 3
  artifacts: []
  missing: []
