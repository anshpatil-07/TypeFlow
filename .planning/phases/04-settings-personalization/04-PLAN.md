---
wave: 1
depends_on: []
files_modified:
  - TypeFlow/UI/SettingsView.swift
  - TypeFlow/Services/SettingsManager.swift
  - TypeFlow/TypeFlowApp.swift
  - TypeFlow/Services/MenuBarManager.swift
  - TypeFlow/Services/AccessibilityMonitor.swift
  - TypeFlow/Services/PromptBuilder.swift
  - TypeFlow/Services/CompletionManager.swift
autonomous: true
---

# Plan 4: Settings & Personalization

## Objective
Provide a SwiftUI settings interface for user customization, including a persona instruction, custom shortcut binding, and an application exclusion list for privacy.

## Requirements Addressed
- **UI-03**: System menu bar icon and menu
- **UI-04**: Settings window (SwiftUI)
- **PERS-01**: User custom instructions / persona prompt
- **PERS-04**: Configurable keyboard shortcut for accept completion
- **CORE-05**: App exclusion list

## Tasks

<task>
<id>settings-manager</id>
<description>Create SettingsManager to manage UserDefaults properties.</description>
<read_first>
- TypeFlow/Services/SettingsManager.swift
</read_first>
<action>
1. Create `TypeFlow/Services/SettingsManager.swift`.
2. Define an `ObservableObject` class `SettingsManager`.
3. Use `@AppStorage` for:
   - `customInstructions` (String, default: "")
   - `acceptShortcut` (String, default: "Tab") // Options: "Tab", "Right Arrow"
   - `excludedApps` (String, default: "com.agilebits.onepassword7,com.apple.keychainaccess") // Stored as CSV string for simplicity with AppStorage
4. Provide helper functions like `isAppExcluded(bundleId: String) -> Bool`.
</action>
<acceptance_criteria>
- `SettingsManager.swift` is implemented and observable.
</acceptance_criteria>
</task>

<task>
<id>settings-ui</id>
<description>Implement SwiftUI Settings window.</description>
<depends_on>settings-manager</depends_on>
<read_first>
- TypeFlow/TypeFlowApp.swift
- TypeFlow/UI/SettingsView.swift
- TypeFlow/Services/MenuBarManager.swift
</read_first>
<action>
1. Create `TypeFlow/UI/SettingsView.swift` containing a `TabView` with two tabs:
   - **General**: Picker for `acceptShortcut`, TextEditor/TextField for `excludedApps`.
   - **Persona**: TextEditor for `customInstructions`.
2. Update `TypeFlow/TypeFlowApp.swift` (or where `@main` is defined if moved) to include a `Settings { SettingsView() }` scene.
3. Update `MenuBarManager.swift` to add a "Settings..." `NSMenuItem`. Its action should call `NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)`.
</action>
<acceptance_criteria>
- Settings window opens from the Menu bar.
- Changes in the UI reflect in `@AppStorage`.
</acceptance_criteria>
</task>

<task>
<id>apply-settings</id>
<description>Integrate settings into the core pipeline.</description>
<depends_on>settings-manager</depends_on>
<read_first>
- TypeFlow/Services/AccessibilityMonitor.swift
- TypeFlow/Services/PromptBuilder.swift
- TypeFlow/Services/CompletionManager.swift
</read_first>
<action>
1. **Shortcut**: Update `AccessibilityMonitor.swift`. Check `SettingsManager.shared.acceptShortcut`. Map "Tab" to `keyCode == 48` and "Right Arrow" to `keyCode == 124`. Only consume the event if the shortcut matches.
2. **Exclusion List**: Update `CompletionManager.onTextChanged()`. Check `NSWorkspace.shared.frontmostApplication?.bundleIdentifier`. If `SettingsManager.shared.isAppExcluded(...)` is true, return immediately and clear any existing completion.
3. **Persona**: Update `PromptBuilder.swift`. If `SettingsManager.shared.customInstructions` is not empty, append it to the prompt: `<custom_instructions>\(instructions)</custom_instructions>`.
</action>
<acceptance_criteria>
- Right Arrow can be used to accept completions.
- App exclusion prevents ghost text in excluded apps.
- Custom instructions are included in the prompt.
</acceptance_criteria>
</task>

## Verification
- Run `xcodebuild` to ensure compilation.
- Ensure the Menu Bar has a working Settings button.
- Verify `SettingsManager` defaults are loaded correctly.
