---
wave: 1
depends_on: []
files_modified:
  - TypeFlow/TypeFlowApp.swift
  - TypeFlow/AppDelegate.swift
  - TypeFlow/Services/AccessibilityMonitor.swift
  - TypeFlow/UI/OverlayWindowController.swift
  - TypeFlow/UI/MenuBarManager.swift
autonomous: true
---

# Plan 1: Core Injection & Foundation

## Objective
Establish the baseline macOS app with Accessibility permissions, a global event tap to detect keystrokes, an overlay window that tracks the text caret, and a menu bar icon.

## Requirements Addressed
- **CORE-01**: System-wide text field monitoring via Accessibility API
- **CORE-02**: Floating transparent overlay window anchored to caret coordinates
- **UI-01**: Launch at login
- **UI-02**: Menu bar icon with quick actions (disable, words saved, settings)

## Tasks

<task>
<id>setup-project</id>
<description>Create the base SwiftUI project structure with App Sandbox exceptions and Accessibility entitlements.</description>
<read_first>
- .planning/ROADMAP.md
</read_first>
<action>
1. Initialize a new SwiftUI macOS project named `TypeFlow` if it doesn't exist.
2. Update `TypeFlow/TypeFlow.entitlements`:
   - Add `<key>com.apple.security.app-sandbox</key><false/>` or appropriate exceptions to allow global Accessibility API usage. (For system-wide event taps, sandbox must often be disabled or we need specific temporary exceptions). Set sandbox to false.
3. Update `TypeFlow/Info.plist`:
   - Add `LSUIElement` set to `YES` to run as an agent app (no dock icon).
   - Add `NSAccessibilityUsageDescription` with value "TypeFlow needs Accessibility access to detect typing and inject completions."
</action>
<acceptance_criteria>
- `TypeFlow/TypeFlow.entitlements` contains `<key>com.apple.security.app-sandbox</key><false/>`
- `TypeFlow/Info.plist` contains `LSUIElement` key set to `<true/>` or `YES`
- Project builds successfully via `xcodebuild`
</acceptance_criteria>
</task>

<task>
<id>menu-bar-ui</id>
<description>Implement the Menu Bar icon and launch at login functionality.</description>
<depends_on>setup-project</depends_on>
<read_first>
- TypeFlow/TypeFlowApp.swift
- .planning/phases/01-core-injection-foundation/01-UI-SPEC.md
</read_first>
<action>
1. Create `TypeFlow/UI/MenuBarManager.swift`.
2. Implement a `MenuBarExtra` or `NSStatusItem` displaying `SF Symbol: text.bubble.fill` (from UI-SPEC).
3. Add a menu with items: "TypeFlow is active" (disabled), "Toggle Globally", "Settings...", "Quit".
4. Use `SMAppService.mainApp.register()` to handle launch at login in a Settings class or App init.
</action>
<acceptance_criteria>
- `TypeFlow/UI/MenuBarManager.swift` contains `NSStatusItem` or `MenuBarExtra` setup
- Menu contains "Quit" and "Settings..." options
</acceptance_criteria>
</task>

<task>
<id>accessibility-monitor</id>
<description>Implement global keystroke monitoring using CGEvent and AXUIElement.</description>
<depends_on>setup-project</depends_on>
<read_first>
- TypeFlow/Services/AccessibilityMonitor.swift
- .planning/phases/01-core-injection-foundation/01-RESEARCH.md
</read_first>
<action>
1. Create `TypeFlow/Services/AccessibilityMonitor.swift`.
2. Implement an `AXIsProcessTrusted()` check. If false, prompt the user to open System Settings via `NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)`.
3. Set up a `CGEvent.tapCreate` for `cghidEventTap` (or `cgsessionEventTap`) listening to `.keyDown`.
4. Implement a callback that checks if the pressed key is Tab (keyCode 48). For now, just print "Tab pressed" and return the event.
5. Create a method `getCurrentCaretRect() -> CGRect?` that:
   - Gets `AXUIElementCreateSystemWide()`
   - Gets the focused UI element (`kAXFocusedUIElementAttribute`)
   - Gets the selected text range (`kAXSelectedTextRangeAttribute`)
   - Gets the bounds for the range (`kAXBoundsForRangeParameterizedAttribute`)
</action>
<acceptance_criteria>
- `AccessibilityMonitor.swift` contains `AXIsProcessTrusted()`
- `AccessibilityMonitor.swift` contains `CGEvent.tapCreate`
- `AccessibilityMonitor.swift` contains `kAXFocusedUIElementAttribute`
</acceptance_criteria>
</task>

<task>
<id>overlay-window</id>
<description>Create a floating transparent window for ghost text rendering.</description>
<depends_on>accessibility-monitor</depends_on>
<read_first>
- TypeFlow/UI/OverlayWindowController.swift
- .planning/phases/01-core-injection-foundation/01-UI-SPEC.md
</read_first>
<action>
1. Create `TypeFlow/UI/OverlayWindowController.swift`.
2. Initialize an `NSWindow` with:
   - `styleMask = .borderless`
   - `level = .floating`
   - `backgroundColor = .clear`
   - `ignoresMouseEvents = true`
3. Add a SwiftUI `HostingView` containing a `Text` element displaying sample ghost text (e.g., " ghost completion").
4. Style the `Text` with `foregroundColor: Color(NSColor.secondaryLabelColor)` and `font: .system(size: 13, weight: .regular)` (from UI-SPEC).
5. Implement `func moveOverlay(to rect: CGRect)` which updates the window's frame to align with the caret rect from `AccessibilityMonitor`.
</action>
<acceptance_criteria>
- `OverlayWindowController.swift` creates an `NSWindow` with `.borderless` and `.clear` background
- Text styling uses `secondaryLabel`
</acceptance_criteria>
</task>

## Must Haves
- App must request Accessibility permissions upon launch if missing.
- App must run headlessly as a menu bar app (no dock icon).
- Keystroke event tap must successfully log Tab key presses system-wide.
- Overlay window must be transparent, borderless, and click-through.

## Verification
- Run `xcodebuild` to ensure the project compiles.
- Manual test: Launch app, verify Accessibility prompt appears.
- Manual test: Grant permission, verify menu bar icon appears.
- Manual test: Focus a text field in Notes, type text, verify overlay window moves to caret position.
