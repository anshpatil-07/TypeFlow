# Phase 18: Adaptive Intelligence - Context

**Gathered:** 2026-06-07
**Status:** Ready for planning

<domain>
## Phase Boundary

Implement adaptive learning behaviors to make the autocomplete engine less intrusive and more personalized: a 2-miss backoff system, dynamic custom lexicon from backspace monitoring, prompt weighting adjustments to prioritize document context over vocabulary, and semantic typo correction that respects the custom lexicon.
</domain>

<decisions>
## Implementation Decisions

### Implicit Learning (2-Miss Backoff)
- **D-01:** Track ignored ghost text suggestions in `CompletionManager`. If an MLX suggestion is ignored 2 consecutive times (user continues typing without hitting Tab/Right Arrow), trigger a "Flow State Backoff" which suspends all automatic MLX completion triggers for 10 seconds to eliminate visual distraction.

### The Dynamic Lexicon (Personalized Autocorrect)
- **D-02:** Monitor backspace events. If the user backspaces over an autocorrected word or a completed word and manually retypes a custom string, save that string to a UserDefaults array called `UserCustomLexicon`.
- **D-03:** Inject `UserCustomLexicon` into the Apple `NSSpellChecker` whitelist and the `PromptBuilder` so the system permanently learns and respects the user's specific shorthand.

### Context vs. Vocabulary Weighting
- **D-04:** Update `PromptBuilder` system instructions to strictly prioritize the `textBeforeCaret` (document context) over the injected personalized vocabulary. Vocabulary should only color the tone, not dictate predicted nouns.

### Semantic Autocorrect Integration
- **D-05:** Enable the MLX engine to silently correct genuine typos based on surrounding context, but strictly forbid it from modifying any words present in the `UserCustomLexicon`.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Source Code References
- `TypeFlow/Services/CompletionManager.swift` — For 2-miss backoff logic
- `TypeFlow/Services/PromptBuilder.swift` — For context vs vocabulary weighting
- `TypeFlow/Services/AccessibilityMonitor.swift` — For tracking backspace events

</canonical_refs>

<specifics>
## Specific Ideas

The user specifically requested:
- 10-second suspension for "Flow State Backoff"
- Save custom strings to `UserCustomLexicon` in UserDefaults
- Inject into Apple `NSSpellChecker` whitelist

</specifics>

<deferred>
## Deferred Ideas

None — PRD covers phase scope
</deferred>

---

*Phase: 18-adaptive-intelligence*
*Context gathered: 2026-06-07 via User Express Override*
