# Phase 5 Research: Tone, Snippets & App Overrides

## Objective
Introduce deeper personalization features, allowing the user to select completion tones, define text replacement snippets, and customize settings on a per-application basis.

## Requirements

### 1. Tone Preferences (PERS-02)
- **API**: `UserDefaults` via `@AppStorage`.
- **Implementation**: Add a "Tone" picker to the General tab in `SettingsView` with options like "Neutral", "Professional", "Casual", and "Concise". Update `PromptBuilder` to include a directive like `Write in a {tone} tone.`

### 2. Snippets (PERS-03)
- **API**: `UserDefaults` with JSON encoding.
- **Implementation**: Allow users to define key-value pairs (e.g., `!email` -> `user@example.com`). In `SettingsView`, provide a list interface to add/remove these. 
- **Integration**: In `CompletionManager.triggerGeneration()`, check if the `activeLine` ends with a snippet key. If it does, immediately resolve the completion to the snippet value, bypassing the LLM entirely.

### 3. App-Specific Overrides (APP-01, APP-02)
- **API**: JSON dictionary in `UserDefaults`.
- **Implementation**: Define a struct `AppConfig: Codable` containing `isEnabled: Bool`, `customTone: String?`, and `customInstructions: String?`. 
- **Integration**: 
  - `SettingsManager` will provide a method to get the effective configuration for the current `bundleIdentifier`.
  - `SettingsView` needs a new "Apps" tab where users can add an application and set its specific configuration.
  - `CompletionManager` uses the effective config to determine if it should run (replacing the simple `excludedApps` logic from Phase 4) and passes the effective tone/instructions to `PromptBuilder`.

## Architecture
- `SettingsManager.swift`: Expand to manage `tone`, `snippets` (Dictionary), and `appConfigs` (Dictionary).
- `SettingsView.swift`: Add UI for Snippets and App Overrides.
- `PromptBuilder.swift`: Accept `tone` and `appInstructions` dynamically.
- `CompletionManager.swift`: Check for snippet matches first; if no match, use effective app config for LLM generation.
