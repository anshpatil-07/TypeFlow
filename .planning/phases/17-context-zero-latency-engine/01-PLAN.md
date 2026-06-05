---
wave: 1
depends_on: []
files_modified:
  - "TypeFlow/Services/AccessibilityMonitor.swift"
  - "TypeFlow/Services/LLMEngine.swift"
  - "TypeFlow/Services/SettingsManager.swift"
  - "TypeFlow/UI/SettingsView.swift"
  - "TypeFlow/Services/PromptBuilder.swift"
  - "TypeFlow/Services/AppMonitor.swift"
autonomous: true
---

# Phase 17 Plan 01: Context & Zero-Latency Engine

<objective>
Implement advanced async context extraction (1000 chars), MLX KV cache pre-warming via NSWorkspace app switch detection, App Voice Map tone switching, and regional spelling toggles.
</objective>

<tasks>

<task>
<description>Update Settings for British English & App Voice Map</description>
<read_first>
- `TypeFlow/Services/SettingsManager.swift`
- `TypeFlow/UI/SettingsView.swift`
</read_first>
<action>
1. In `SettingsManager.swift`, add a published boolean property `useBritishEnglish` defaulting to `false` (AppStorage key: "useBritishEnglish").
2. In `SettingsManager.swift`, add a published dictionary property `appVoiceMap` of type `[String: String]` defaulting to empty (AppStorage key: "appVoiceMap"). This maps bundle identifiers to tone profile IDs.
3. In `SettingsView.swift`, add a simple Toggle for "Use British English" bound to `settingsManager.useBritishEnglish`.
</action>
<acceptance_criteria>
- `SettingsManager.swift` contains `@AppStorage("useBritishEnglish") public var useBritishEnglish: Bool = false`
- `SettingsManager.swift` contains `@AppStorage("appVoiceMap") public var appVoiceMap: [String: String] = [:]` (or equivalent UserDefaults wrapper if AppStorage doesn't support dictionaries natively, e.g., using `RawRepresentable` or custom setter/getter with JSON encoding).
- `SettingsView.swift` contains `Toggle("Use British English", isOn: $settingsManager.useBritishEnglish)`
</acceptance_criteria>
</task>

<task>
<description>Implement PromptBuilder Regional Spelling</description>
<read_first>
- `TypeFlow/Services/PromptBuilder.swift`
- `TypeFlow/Services/SettingsManager.swift`
</read_first>
<action>
1. In `PromptBuilder.swift`, when constructing the system prompt, check `SettingsManager.shared.useBritishEnglish`.
2. If `true`, inject the exact string: `Always use British English spelling (e.g., colour, prioritise).` into the base system prompt before generating the final prompt string.
</action>
<acceptance_criteria>
- `PromptBuilder.swift` contains `if SettingsManager.shared.useBritishEnglish {`
- `PromptBuilder.swift` contains the exact string `"Always use British English spelling (e.g., colour, prioritise)."`
</acceptance_criteria>
</task>

<task>
<description>Implement NSWorkspace AppMonitor for Zero-Latency Pre-warming & Chameleon Tone</description>
<read_first>
- `TypeFlow/Services/LLMEngine.swift`
- `TypeFlow/Services/SettingsManager.swift`
</read_first>
<action>
1. Create a new service `TypeFlow/Services/AppMonitor.swift`.
2. In `AppMonitor`, subscribe to `NSWorkspace.shared.notificationCenter.addObserver` for `NSWorkspace.didActivateApplicationNotification`.
3. In the handler, extract the `bundleIdentifier` of the activated app (`notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication`).
4. Check `SettingsManager.shared.appVoiceMap[bundleIdentifier]`. If it exists, update `SettingsManager.shared.activeToneProfile` to this value.
5. In `LLMEngine.swift`, add a public method `prewarmCache(bundleIdentifier: String, toneProfile: String?)`.
6. In `prewarmCache`, dispatch a background task to pre-fill the MLX KV cache with the base system prompt and the current tone. (If MLX Swift API provides `eval` or a generator pass without sampling, use it to process the static prefix).
7. Call `LLMEngine.shared.prewarmCache` from `AppMonitor.swift` on every app switch.
</action>
<acceptance_criteria>
- `TypeFlow/Services/AppMonitor.swift` exists and contains `NSWorkspace.didActivateApplicationNotification` observer.
- `AppMonitor.swift` checks `appVoiceMap[bundleId]` and updates the tone profile.
- `LLMEngine.swift` contains `func prewarmCache(`
- `AppMonitor.swift` calls `LLMEngine.shared.prewarmCache`
</acceptance_criteria>
</task>

<task>
<description>Upgrade AccessibilityMonitor Context Extraction</description>
<read_first>
- `TypeFlow/Services/AccessibilityMonitor.swift`
</read_first>
<action>
1. In `AccessibilityMonitor.swift` (inside the `triggerContextFetch` method running on the `.utility` queue), upgrade the `AXUIElement` query to fetch up to the last 1,000 characters of text before the caret.
2. Use `AXUIElementCopyParameterizedAttributeValue` with `kAXStringForRangeParameterizedAttribute` if possible, or fetch the full `kAXValueAttribute` and substring the last 1000 characters based on the caret position `kAXSelectedTextRangeAttribute`.
3. Ensure this logic is only executed within the 150ms debounce block or the immediate end-of-word (space/punctuation) block.
</action>
<acceptance_criteria>
- `AccessibilityMonitor.swift` contains logic to limit context extraction to a max of 1000 characters (e.g., `let start = max(0, caretIndex - 1000)`).
- The fetch logic remains inside the `.utility` queue dispatch block and the debounced `contextFetchWorkItem`.
</acceptance_criteria>
</task>

</tasks>

<must_haves>
- Settings toggle for British English.
- App Voice Map correctly switches tone on app switch.
- NSWorkspace listener pre-warms the MLX KV cache on app switch.
- AccessibilityMonitor extracts up to 1000 characters on the .utility queue.
</must_haves>

<verification_criteria>
- Build passes without errors.
- Toggling "Use British English" adds the prompt instruction.
- Switching to an app mapped in `appVoiceMap` automatically switches the tone.
- Switching apps triggers `LLMEngine.prewarmCache`.
- Typing extracts exactly the last 1000 characters (or less if the text field is smaller) without dropping spaces or freezing the UI.
</verification_criteria>
