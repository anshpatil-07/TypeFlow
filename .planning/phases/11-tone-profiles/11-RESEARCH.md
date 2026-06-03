# Phase 11: Tone Profiles - Research

## Objective
Implement custom completion tones (profiles with custom instructions, temperature, and length parameters), replace the 'Persona' settings tab with a 'Tones' settings tab, and update app overrides to support custom tones.

## Technical Details

### 1. Storage & Model (`SettingsManager.swift`)
We need a Swift model representing a Tone Profile:
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
Built-in profiles will be hardcoded defaults:
- **Neutral**: Temp `0.2`, Max Tokens `20`
- **Professional**: Temp `0.1`, Max Tokens `20`
- **Casual**: Temp `0.4`, Max Tokens `25`
- **Concise**: Temp `0.0`, Max Tokens `10`

Custom profiles will be stored as a JSON-encoded array under a new `@AppStorage("customTonesData")` key in `SettingsManager`. We will provide a helper function `getToneProfile(by id: String)` to resolve the active profile.

`AppConfig` will keep storing `customTone` (representing the tone's ID/name).

### 2. Prompt Injection (`PromptBuilder.swift`)
Instead of hardcoding instructions inside `buildPrompt`, we will parameterize it:
```swift
func buildPrompt(textBeforeCaret: String, systemInstructions: String) -> String
```
This allows dynamically applying instructions corresponding to the selected tone profile.

### 3. Dynamic Inference Parameters (`LLMEngine.swift` & `CompletionManager.swift`)
- In `LLMEngine.swift`, update `generateCompletion` to accept a `ToneProfile` object instead of simple `tone` and `customInstructions` strings.
- Map the tone profile parameters to the `GenerateParameters` initialization:
```swift
let params = GenerateParameters(
    maxTokens: toneProfile.maxTokens,
    temperature: Float(toneProfile.temperature)
)
```

### 4. UI Refactoring (`SettingsView.swift`)
- Replace the "Persona" tab with a "Tones" tab featuring a sidebar list of all tone profiles (grouped by Built-in and Custom).
- Include controls to add a custom tone, duplicate any tone, and delete custom tones.
- Provide sliders for Temperature (0.0 to 1.0) and Max Tokens (5 to 50).
- Fully implement App Overrides list/detail editing (which was stubbed in earlier phases) to enable testing the dynamic tone overrides.
- Fully implement Snippets tab editing to complete settings functionality.

## Verification Architecture

### Automated Verification
Since MLX inference runs on-device, we will write a command-line script/playground to verify:
1. Storing and loading custom tone profiles via JSON encoding.
2. Resolution of effective configuration for app overrides.
3. Correct compilation of prompt and mapping of parameters.

### Manual Verification
1. Open Settings -> Tones: Create a custom tone.
2. Edit its instructions (e.g. "Answer like a pirate"), temperature, and length.
3. Open Apps: Assign this tone to an editor (e.g. TextEdit).
4. Type in TextEdit and verify completions use the custom tone rules.
5. Check debug output logs in Xcode or Console to verify the correct temperature and max tokens were passed to the MLX generator.
