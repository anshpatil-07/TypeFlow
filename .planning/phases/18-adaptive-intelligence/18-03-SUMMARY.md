---
phase: 18
plan: "18-03"
subsystem: "TypeFlow/Services"
tags: ["gap-closure", "prompt-engineering"]
requires: []
provides: ["lexicon-hallucination-prevention"]
affects: ["PromptBuilder"]
tech-stack.added: []
key-files.modified: ["TypeFlow/Services/PromptBuilder.swift"]
key-decisions: ["Softened the vocabulary context formatting and added strict negative constraint to prevent model from reciting the custom lexicon words as a list."]
requirements-completed: []
duration: "1 min"
completed: "2026-06-07T09:24:00Z"
---

# Phase 18 Gap Plan: Lexicon Hallucination Fix Summary

Fixed a hallucination issue where the LLM ignored document context and generated a literal comma-separated list of the injected vocabulary words.

## Work Completed
- In `PromptBuilder.swift`, updated the formatting for injected vocabulary from `[User vocabulary & jargon]:` to a softer `[Passive Stylistic Vocabulary Influence]:`.
- Added a strict negative constraint: `CRITICAL: You are an invisible autocomplete engine. DO NOT recite, list, or explicitly mention the provided vocabulary words. Only use them naturally if they flawlessly fit the immediate grammatical context of the suffix. Prioritize the user's document context above all else.`
- Separated instructions using an explicit `[System Instructions]:` header to prevent prompt leakage and blending with user text.

## Next Steps
User should run `/gsd-verify-work 18` again to re-test the lexicon protection.
