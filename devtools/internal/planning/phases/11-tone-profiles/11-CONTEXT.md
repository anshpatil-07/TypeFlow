# Phase 11: Tone Profiles - Context

**Gathered:** 2026-06-03
**Status:** Ready for planning

<domain>
## Phase Boundary

This phase delivers custom Tone Profiles for TypeFlow, allowing users to define, edit, and delete their own custom completion tones (consisting of custom instructions, temperature, and length parameters) via the Settings UI and assign them globally or on a per-app basis.

</domain>

<decisions>
## Implementation Decisions

### 1. UI Integration (Tones Tab)
- **D-01**: Replace the existing 'Persona' tab in the Settings window with a 'Tones' tab.
- **D-02**: The Tones tab will feature a sidebar or list containing all available tones (both built-in and user-created). Selecting a tone will display an editor panel for its details.

### 2. Tone Profile Parameters
- **D-03**: Each tone profile will support the following fields:
  - **Name**: A user-defined string.
  - **Custom Instructions**: Text instruction detailing how the LLM should complete text (replacing the default or custom persona instructions).
  - **Temperature**: A slider ranging from 0.0 to 1.0 (representing creativity/randomness, mapping to MLX inference parameters).
  - **Max Token Length**: An integer input or slider specifying the maximum length of generated completions (clamped to a safe default like 50).

### 3. Built-in vs Custom Tones Behavior
- **D-04**: The default built-in tones (Neutral, Professional, Casual, Concise) are read-only defaults. They cannot be renamed, edited, or deleted.
- **D-05**: Users can duplicate any built-in or custom tone to create a new custom tone profile.
- **D-06**: Custom tone profiles can be fully edited, renamed, and deleted.

### 4. App Overrides Integration
- **D-07**: The Tone picker in the Apps tab (App Overrides) will dynamically list all user-created custom tone profiles in addition to the default built-in tones.
- **D-08**: Selection of a custom tone in app overrides is saved via its unique ID or name in `AppConfig`.

### the agent's Discretion
- The exact layout styling of the Tones list/sidebar and editing controls (Form controls, layout spacing, delete confirmation dialogues).
- The storage implementation for custom tone profiles in `SettingsManager` (e.g. JSON-encoded dictionary in `UserDefaults` or `@AppStorage` under a specific key like `"toneProfilesData"`).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Settings & UI
- `TypeFlow/UI/SettingsView.swift` — Defines Settings tab layouts and bindings.
- `TypeFlow/Services/SettingsManager.swift` — Stores configurations and App Storage values.

### Prompting & Inference
- `TypeFlow/Services/PromptBuilder.swift` — Injecting tone parameters and custom instructions.
- `TypeFlow/Services/LLMEngine.swift` — Running inference using temperature and max tokens.
- `TypeFlow/Services/CompletionManager.swift` — Managing completion pipelines and app configurations.

</canonical_refs>

<specifics>
## Specific Ideas
- Custom tone profiles should default to a safe temperature (e.g. 0.2) and max token length (e.g. 20) upon creation.
</specifics>

<deferred>
## Deferred Ideas
- None — all discussed scope falls within Phase 11.
</deferred>
