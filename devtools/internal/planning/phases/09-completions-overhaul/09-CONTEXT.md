# Phase 9: Completions Overhaul - Context

**Gathered:** 2026-05-23
**Status:** Ready for planning

<domain>
## Phase Boundary

Fixing and optimizing the completion generation and insertion pipeline to be robust, visually correct, and reliable. This includes generation lifecycle, ghost text styling, tab interception, and edge case handling.

</domain>

<decisions>
## Implementation Decisions

### Generation Lifecycle
- **D-01:** Cancel in-flight LLM generation immediately on any new keystroke to save CPU/battery.
- **D-02:** Use a 150ms debounce timing before triggering generation for an aggressive, instant feel.

### Ghost Text Styling
- **D-03:** Use standard system font (SF Pro) with a generic gray color — robust and works everywhere.
- **D-04:** No animation for the ghost text, just appear instantly to meet the <150ms latency target.

### Tab Interception Strategy
- **D-05:** Intercept Tab using a CGEvent tap (intercepts globally before target app receives it) when ghost text is visible.
- **D-06:** Pass the Tab event through to the target app untouched if no ghost text is visible.

### Edge Case Handling
- **D-07:** Silently ignore it and hide any ghost text if the model outputs nothing (or just whitespace).
- **D-08:** Strip the echoed prefix before displaying the ghost text if the model generates text that exactly matches what the user is currently typing.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### App Context
- `.planning/PROJECT.md` — Core value constraints, architecture constraints.
- `.planning/REQUIREMENTS.md` — Requirements and current milestone details.

</canonical_refs>
