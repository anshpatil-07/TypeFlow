# Phase 15: Context-Aware Smart Reply - Context

**Gathered:** 2026-06-04
**Status:** Ready for planning

<domain>
## Phase Boundary

Context-Aware Smart Reply: Generating and presenting context-aware short reply options based on on-screen conversations by combining Accessibility API text and Vision OCR, triggered via global shortcut, and presented as a 3-option popover.

</domain>

<decisions>
## Implementation Decisions

### UI Presentation
- **D-01:** Popover with 3 options: Reuses Phase 14 Rewrite UI pattern, user clicks/selects one.

### Trigger Mechanism
- **D-02:** Manual global shortcut (e.g., Cmd+Shift+R). Predictable, avoids accidental popovers.

### Tone Selection
- **D-03:** Always generate 3 diverse options (e.g., Professional, Casual, Concise) and let user pick.

### Context Extraction
- **D-04:** Both: Combine Accessibility API text + recent Vision OCR text from ScreenContextManager (Most comprehensive).

### the agent's Discretion
- Exact sizing and layout constraints of the popover options list.
- Specific shortcut default if Cmd+Shift+R conflicts with standard macOS shortcuts.
- Merging strategy for combining Accessibility Text and Vision OCR text to prevent duplicates in the LLM prompt.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### App Context
- `.planning/PROJECT.md` — Core value constraints, architecture constraints.
- `.planning/REQUIREMENTS.md` — Requirements and current milestone details.
- `.planning/phases/14-rewrite-on-selection/14-CONTEXT.md` — For the Popover UI pattern to be reused.

</canonical_refs>

<specifics>
## Specific Ideas
- Generate exactly 3 reply variations (e.g., Professional, Casual, Concise).
- Use `ScreenContextManager` and `AccessibilityMonitor` to capture context before feeding to `LLMEngine`.
</specifics>

<deferred>
## Deferred Ideas
None
</deferred>
