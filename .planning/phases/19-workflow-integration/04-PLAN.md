---
plan: 19-04
phase: 19-workflow-integration
status: pending
dependencies: []
---

# Plan 04: Gap Closure (UAT Fixes)

This plan addresses the 4 issues discovered during UAT for Phase 19. The fixes handle AppShortcuts startup crashes, missing clipboard monitor initialization, missing NSServices configurations in Info.plist, and incorrect Obj-C signatures for system services.

## Objective
Implement all missing configurations and asynchronous wrappers to ensure macOS correctly integrates TypeFlow's workflow features (Services, Shortcuts, Clipboard) without crashing the app.

## Proposed Changes

### 1. Apple Shortcuts Race Condition (Gap 1)
- **File:** `TypeFlow/AppDelegate.swift`
- **Action:** [MODIFY]
- **Details:** Wrap `TypeFlowShortcuts.updateAppShortcutParameters()` inside a `Task { do { ... } catch { ... } }` to ensure it runs asynchronously and does not block the main thread, avoiding `NSCocoaErrorDomain Code=4097` crashes with the macOS `linkd` daemon. *(Note: This was partially done during UAT but needs to be officially executed/verified).*

### 2. Clipboard Monitor Initialization & Trigger Logic (Gap 2)
- **File:** `TypeFlow/AppDelegate.swift`
- **Action:** [MODIFY]
- **Details:** Ensure `ClipboardMonitor.shared.start()` is explicitly called within `applicationDidFinishLaunching`, immediately following `AppMonitor.shared.start()`.
- **File:** `TypeFlow/Services/PromptBuilder.swift`
- **Action:** [MODIFY]
- **Details:** In `buildPromptSuffix`, trim trailing whitespaces from `lowercasedText` before checking if it `.hasSuffix` against the `clipboardTriggers` array. This prevents the trigger from failing when the user naturally types a space after the colon.

### 3. NSServices Info.plist & Obj-C Signatures (Gap 3)
- **File:** `project.yml`
- **Action:** [MODIFY]
- **Details:** Add an `NSServices` array under `info: properties:` so that `xcodegen` permanently includes it in `Info.plist`. The array must include dictionaries for `rewriteText` and `expandText`, specifying `NSMenuItem`, `NSMessage`, `NSPortName` (TypeFlow), `NSSendTypes` (String), and `NSReturnTypes` (String).
- **File:** `TypeFlow/Services/NSServicesProvider.swift`
- **Action:** [MODIFY]
- **Details:** Update the `@objc func rewriteText` and `expandText` signatures to correctly map to the Objective-C runtime requirements by making the `userData` and `error` generic types optional: `userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>`.

### 4. Dynamic Services Registration (Gap 4)
- **File:** `TypeFlow/AppDelegate.swift`
- **Action:** [MODIFY]
- **Details:** Immediately after assigning `NSApp.servicesProvider = TypeFlowServicesProvider()`, call `NSUpdateDynamicServices()` to force macOS to register the services instantly, avoiding the need for a system restart or PBS cache flush.

## Verification
- App launches cleanly without `com.apple.linkd.autoShortcut` crashes.
- "Rewrite with TypeFlow" and "Expand with TypeFlow" appear in the right-click Services menu across the system (e.g., in TextEdit).
- Typing "here is the link: " (with a space) successfully pulls context from the clipboard.
- "Rewrite with TypeFlow" intent is available and works in the Shortcuts app.
