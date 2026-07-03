# Phase 4 Research: Settings & Personalization

## Objective
Provide a SwiftUI settings interface to allow users to customize their AI assistant's persona, change shortcut bindings, and define exclusion lists for privacy.

## Requirements

### 1. Settings Window (UI-04)
- **API**: SwiftUI `Settings` scene.
- **Implementation**: Add `Settings { SettingsView() }` to the main `App` struct. The `SettingsView` can use `TabView` for multiple panes (General, Persona, Advanced).

### 2. User Custom Instructions (PERS-01)
- **API**: `UserDefaults` via `@AppStorage`.
- **Implementation**: A `TextEditor` in `SettingsView`. We will need to update `PromptBuilder` to inject these instructions into the system prompt. For example: `The user has provided the following custom instructions: {custom_instructions}`.

### 3. Configurable Keyboard Shortcut (PERS-04)
- **API**: `UserDefaults` via `@AppStorage`.
- **Implementation**: A `Picker` in `SettingsView` allowing choices like "Tab", "Right Arrow", or "Shift + Tab". 
- **Integration**: `AccessibilityMonitor` needs to read this preference to know which `keyCode` and flags to intercept.

### 4. App Exclusion List (CORE-05)
- **API**: `NSWorkspace.shared.frontmostApplication?.bundleIdentifier`
- **Implementation**: Store a list of excluded bundle identifiers (e.g., `com.agilebits.onepassword7`) in `UserDefaults`. 
- **Integration**: Before extracting context or triggering a completion in `CompletionManager`, check if the active app is excluded. If so, abort immediately.

### 5. Menu Bar Icon (UI-03)
- **API**: `NSMenu` and `NSStatusBar` (Already partially implemented).
- **Implementation**: Add a "Settings..." item to the menu that triggers `NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)` to open the SwiftUI settings window programmatically.

## Architecture
- `SettingsView.swift`: The main SwiftUI UI for settings.
- `SettingsManager.swift`: A centralized observable object for managing preferences.
- Integration points:
  - `AccessibilityMonitor.swift` (shortcut interception).
  - `PromptBuilder.swift` (custom instructions).
  - `CompletionManager.swift` (exclusion checking).
