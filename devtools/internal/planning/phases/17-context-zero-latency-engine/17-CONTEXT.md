# Phase 17: Context & Zero-Latency Engine - Context

**Gathered:** 2026-06-05
**Status:** Ready for planning

<domain>
## Phase Boundary

This phase delivers the core context extraction pipeline (fetching up to 1000 chars) and the "Zero-Latency" MLX KV cache pre-warming mechanics to hit the 150ms completion target. It also introduces app-specific tone switching and regional spelling preferences.

</domain>

<decisions>
## Implementation Decisions

### 1. Advanced Async Context Extraction
- **D-01:** Upgrade `AccessibilityMonitor` to pull the last 1,000 characters of text from the active `AXUIElement`.
- **D-02:** This extraction MUST remain strictly on the background `.utility` queue established in Phase 16, triggered only on the debounce timer or end-of-word (space/punctuation) to prevent main-thread stuttering.

### 2. The Zero-Latency Engine (MLX Pre-warming)
- **D-03:** Subscribe to `NSWorkspace.didActivateApplicationNotification`.
- **D-04:** When the user switches to a new application, silently dispatch a task to `LLMEngine` to pre-fill the KV cache with the base system prompt and tone. By the time the user starts typing, the GPU should already be primed for the suffix.

### 3. The Chameleon Tone Engine
- **D-05:** Create an "App Voice Map" (stored in `UserDefaults`).
- **D-06:** When `NSWorkspace` detects an app switch, check the new app's `bundleIdentifier`. If it matches a configured app (e.g., `com.apple.dt.Xcode`), automatically switch the active tone profile (e.g., to "Software Engineer") and pass this into the MLX Pre-warming step.

### 4. British vs. American English Toggle
- **D-07:** Add a simple boolean toggle to the Settings SwiftUI view for "Use British English".
- **D-08:** Update `PromptBuilder` so that if this is true, it strictly injects "Always use British English spelling (e.g., colour, prioritise)" into the static system prompt.

### the agent's Discretion
- Implementation details of `UserDefaults` structure for the App Voice Map.
- How exactly to pre-fill the MLX KV cache safely in the background.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project Core
- `.planning/PROJECT.md` — Core vision and performance targets
- `.planning/REQUIREMENTS.md` — Active requirements and constraints
- `TypeFlow/Services/AccessibilityMonitor.swift` — The source for the `.utility` queue constraints.
- `TypeFlow/Services/LLMEngine.swift` — Target for MLX KV Cache pre-warming.

</canonical_refs>
