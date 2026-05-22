---
wave: 1
depends_on: []
files_modified:
  - TypeFlow/Services/SettingsManager.swift
  - TypeFlow/UI/SettingsView.swift
  - TypeFlow/Services/PromptBuilder.swift
  - TypeFlow/Services/CompletionManager.swift
autonomous: true
---

# Plan 5: Tone, Snippets & App Overrides

## Objective
Introduce deeper personalization features, allowing the user to select completion tones, define text replacement snippets, and customize settings on a per-application basis.

## Requirements Addressed
- **PERS-02**: User tone preference
- **PERS-03**: Custom shortcuts / text replacement snippets
- **APP-01**: App-specific configurations
- **APP-02**: Conditional completion activation per app

## Tasks

<task>
<id>settings-manager-updates</id>
<description>Update SettingsManager to support Tone, Snippets, and App Configs.</description>
<read_first>
- TypeFlow/Services/SettingsManager.swift
</read_first>
<action>
1. Update `TypeFlow/Services/SettingsManager.swift`.
2. Add `@AppStorage("tone") var tone: String = "Neutral"`.
3. Add `@AppStorage("snippetsData") var snippetsData: Data = Data()`. Provide accessors to encode/decode `[String: String]` dictionary for Snippets.
4. Add `@AppStorage("appConfigsData") var appConfigsData: Data = Data()`. Provide accessors to encode/decode `[String: AppConfig]` dictionary, where `AppConfig` has `isEnabled: Bool`, `customTone: String?`, and `customInstructions: String?`.
5. Create `func getEffectiveConfig(for bundleId: String) -> (isEnabled: Bool, tone: String, instructions: String)`. This replaces `isAppExcluded(bundleId:)` from Phase 4.
</action>
<acceptance_criteria>
- `SettingsManager` stores and retrieves complex data via JSON-encoded Data in `AppStorage`.
- `getEffectiveConfig` accurately resolves per-app vs global settings.
</acceptance_criteria>
</task>

<task>
<id>settings-ui-updates</id>
<description>Update SettingsView with Tone Picker, Snippets List, and App Configs List.</description>
<depends_on>settings-manager-updates</depends_on>
<read_first>
- TypeFlow/UI/SettingsView.swift
</read_first>
<action>
1. Update `TypeFlow/UI/SettingsView.swift`.
2. **General Tab**: Add Tone Picker ("Neutral", "Professional", "Casual", "Concise").
3. **Snippets Tab (New)**: A UI to view, add, and remove Snippet mappings (Key -> Value).
4. **Apps Tab (New)**: A UI to view, add, and edit `AppConfig` items for specific bundle identifiers. Remove the basic CSV-based exclusion list text editor from Phase 4.
</action>
<acceptance_criteria>
- Settings window contains 4 tabs: General, Persona, Snippets, Apps.
- Users can manipulate snippets and app overrides.
</acceptance_criteria>
</task>

<task>
<id>apply-tone-and-snippets</id>
<description>Integrate Tone, Snippets, and App Overrides into the Core Pipeline.</description>
<depends_on>settings-manager-updates</depends_on>
<read_first>
- TypeFlow/Services/PromptBuilder.swift
- TypeFlow/Services/CompletionManager.swift
</read_first>
<action>
1. **CompletionManager.swift**: 
   - In `onTextChanged()`, check `SettingsManager.shared.getEffectiveConfig(for: bundleId)`. If `!isEnabled`, return immediately.
   - In `triggerGeneration()`, *before* building the prompt, check if the `activeLine` ends with a defined snippet key. If yes, directly set `self.currentCompletion = snippetValue` and `updateText(snippetValue)` without invoking `LLMEngine`.
2. **PromptBuilder.swift**:
   - Update `buildPrompt(context:tone:instructions:)` to accept the dynamically resolved tone and instructions from the `getEffectiveConfig` lookup.
   - Inject the tone directive into the prompt: `Adopt a \(tone) tone.`
</action>
<acceptance_criteria>
- Snippets trigger instantly without MLX inference.
- App-specific overrides dictate activation and prompt configuration.
- The prompt includes the correct tone.
</acceptance_criteria>
</task>

## Verification
- Run `xcodebuild` to ensure compilation.
- Ensure the Settings window displays the new tabs and persists data.
