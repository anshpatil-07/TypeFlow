---
wave: 1
depends_on: []
files_modified:
  - TypeFlow/Services/SettingsManager.swift
  - TypeFlow/Services/PromptBuilder.swift
  - TypeFlow/Services/LLMEngine.swift
  - TypeFlow/Services/CompletionManager.swift
  - TypeFlow/UI/SettingsView.swift
autonomous: true
---

# Plan 11: Tone Profiles

## Objective
Implement custom completion tones (profiles with custom instructions, temperature, and length parameters), replace the 'Persona' settings tab with a 'Tones' settings tab, and update app overrides to support custom tones.

## Requirements Addressed
- **TONE-01**: Custom tone profiles defining instructions, temperature (0.0 to 1.0), and max completion length.
- **TONE-02**: Read-only built-in default tones (Neutral, Professional, Casual, Concise) and duplicable.
- **TONE-03**: Tones UI Sidebar/Master-Detail in Settings window.
- **TONE-04**: Dynamically populated App Overrides with custom tone picker.

## Tasks

<task>
<id>tone-profile-model</id>
<description>Create the ToneProfile struct, add storage functions, and update effective config lookups in SettingsManager.</description>
<read_first>
- TypeFlow/Services/SettingsManager.swift
</read_first>
<action>
1. Define the `ToneProfile` struct conforming to `Codable`, `Identifiable`, and `Hashable`:
   ```swift
   struct ToneProfile: Codable, Identifiable, Hashable {
       var id: String
       var name: String
       var systemInstructions: String
       var temperature: Double
       var maxTokens: Int
       var isBuiltIn: Bool
   }
   ```
2. Add static property `builtInTones` to `SettingsManager`:
   - Neutral: temp 0.2, maxTokens 20, instructions "Complete the text. Output only the next few words. No explanation."
   - Professional: temp 0.1, maxTokens 20, instructions "Complete the text in a professional, formal, and polite tone. Output only the next few words. No explanation."
   - Casual: temp 0.4, maxTokens 25, instructions "Complete the text in a friendly, casual, and conversational tone. Output only the next few words. No explanation."
   - Concise: temp 0.0, maxTokens 10, instructions "Complete the text extremely concisely. Output only the next one or two words. No explanation."
3. Add `@AppStorage("customTonesData") var customTonesData: Data = Data()` to `SettingsManager`.
4. Add helper functions:
   - `getCustomTones() -> [ToneProfile]`
   - `saveCustomTones(_ tones: [ToneProfile])`
   - `getTones() -> [ToneProfile]` (returns built-in + custom tones)
   - `getToneProfile(by id: String) -> ToneProfile`
5. Update `getEffectiveConfig(for bundleId: String)` to return `(isEnabled: Bool, toneProfile: ToneProfile)`. Look up the tone profile and apply `customInstructions` override if present.
</action>
<acceptance_criteria>
- `SettingsManager.swift` contains the `ToneProfile` struct.
- `SettingsManager.swift` contains `getEffectiveConfig` returning a `ToneProfile` as the second element of the tuple.
</acceptance_criteria>
</task>

<task>
<id>prompt-builder-updates</id>
<description>Update PromptBuilder to accept system instructions dynamically.</description>
<read_first>
- TypeFlow/Services/PromptBuilder.swift
</read_first>
<action>
1. Modify `buildPrompt(textBeforeCaret: String)` to:
   ```swift
   func buildPrompt(textBeforeCaret: String, systemInstructions: String) -> String
   ```
2. Replace the hardcoded instruction `"Complete the text. Output only the next few words. No explanation.\n\n"` with the dynamic `systemInstructions`.
</action>
<acceptance_criteria>
- `PromptBuilder.swift` contains `func buildPrompt(textBeforeCaret: String, systemInstructions: String) -> String`.
- The hardcoded system instruction is replaced with `systemInstructions`.
</acceptance_criteria>
</task>

<task>
<id>llm-engine-updates</id>
<description>Update LLMEngine to receive ToneProfile and apply its temperature and token length parameters dynamically.</description>
<read_first>
- TypeFlow/Services/LLMEngine.swift
</read_first>
<action>
1. Update the signature of `generateCompletion` to:
   ```swift
   func generateCompletion(textBeforeCaret: String, toneProfile: ToneProfile) async -> String
   ```
2. Update the `buildPrompt` call to pass `toneProfile.systemInstructions`.
3. Update `GenerateParameters` inside `generateCompletion` to use the profile's values:
   ```swift
   let params = GenerateParameters(maxTokens: toneProfile.maxTokens, temperature: Float(toneProfile.temperature))
   ```
</action>
<acceptance_criteria>
- `LLMEngine.swift` contains `generateCompletion(textBeforeCaret: String, toneProfile: ToneProfile)`.
- `GenerateParameters` dynamically uses `toneProfile.maxTokens` and `Float(toneProfile.temperature)`.
</acceptance_criteria>
</task>

<task>
<id>completion-manager-updates</id>
<description>Update CompletionManager to pass the effective tone configuration to the inference engine.</description>
<read_first>
- TypeFlow/Services/CompletionManager.swift
</read_first>
<action>
1. Update `CompletionManager.swift` where `generateCompletion` is called (inside `triggerGeneration`).
2. Retrieve `effectiveConfig` from `SettingsManager.shared.getEffectiveConfig(for: bundleId)`.
3. Pass `effectiveConfig.toneProfile` to `LLMEngine.shared.generateCompletion`.
</action>
<acceptance_criteria>
- `CompletionManager.swift` calls `LLMEngine.shared.generateCompletion(textBeforeCaret: activeLine, toneProfile: effectiveConfig.toneProfile)`.
</acceptance_criteria>
</task>

<task>
<id>settings-ui-updates</id>
<description>Implement TonesSettingsView, replace Persona tab, and implement AppOverridesSettingsView and SnippetsSettingsView.</description>
<read_first>
- TypeFlow/UI/SettingsView.swift
</read_first>
<action>
1. Modify `SettingsView.swift` to increase window frame to `.frame(width: 600, height: 450)`.
2. Update General Tab picker for tone to list all tones dynamically using `settings.getTones()`.
3. Create `TonesSettingsView` with:
   - Sidebar/List showing all built-in and custom tone profiles.
   - Buttons to Add, Delete, and Duplicate tones.
   - Form-based editor panel displaying Name, Instructions (TextEditor), Temperature (Slider), and Max Length (Slider). Built-in tones are read-only; custom tones bind directly to custom tones storage.
4. Replace the "Persona" tab view with `TonesSettingsView()`.
5. Implement `AppOverridesSettingsView` in the Apps tab displaying App Config sidebar list, Add/Delete buttons, toggle for enabled, and Picker for tone profile selection (along with optional custom instructions text editor).
6. Implement `SnippetsSettingsView` in the Snippets tab showing current snippets in a list, Add form, and Trash delete button.
</action>
<acceptance_criteria>
- `SettingsView.swift` does not contain any visually stubbed placeholders in the Tabs.
- Tones Tab is named "Tones" and renders `TonesSettingsView`.
- Apps Tab renders `AppOverridesSettingsView`.
- Snippets Tab renders `SnippetsSettingsView`.
</acceptance_criteria>
</task>

## Must Haves
- Custom tone profiles must support custom names, instructions, temperature sliders, and token lengths.
- Built-in tones must remain read-only but be duplicable.
- Settings UI tabs (Persona, Snippets, Apps) must be fully functional and contain no placeholder stubs.
- In-context inference must dynamically use the tone profile's parameters.

## Verification
- Write a test runner script (`TypeFlow/scratch/test_tone_profiles.swift`) to test the JSON serialization, profile listing, and parameter mapping.
- Run the TypeFlow app and manually check creation, deletion, duplication, and settings overrides in the UI.
