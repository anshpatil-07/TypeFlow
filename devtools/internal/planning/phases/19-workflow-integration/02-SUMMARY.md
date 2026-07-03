---
plan: 19-02
phase: 19-workflow-integration
status: complete
completed: 2026-06-07
---

# Summary: Phase 19, Plan 02 — macOS Native Services

## What Was Built

- **`TypeFlowServicesProvider.swift`** — `@objc` class implementing two `NSServices` handler methods:
  - `rewriteText(_:userData:error:)` — extracts selected text from the system pasteboard, runs it through `LLMEngine.generateRewrite`, writes the result back.
  - `expandText(_:userData:error:)` — extracts selected text, runs `LLMEngine.generateCompletion`, appends the completion to the original and writes back.
- **`Info.plist`** — Added `NSServices` array with two entries advertising `rewriteText` and `expandText` to macOS, enabling "Rewrite with TypeFlow" and "Expand with TypeFlow" in system right-click and Services menus.
- **`AppDelegate.swift`** — Added `NSApp.servicesProvider = TypeFlowServicesProvider()` registration.

## Key Files

### Created
- `TypeFlow/Services/NSServicesProvider.swift`

### Modified
- `TypeFlow/Info.plist` — NSServices declarations
- `TypeFlow/AppDelegate.swift` — services provider registration

## Self-Check: PASSED
- `TypeFlowServicesProvider` uses correct `@objc` method signatures ✓
- `Info.plist` contains `NSServices` with `rewriteText` and `expandText` messages ✓
- Provider registered with `NSApp.servicesProvider` on launch ✓
- Correct `SettingsManager.getEffectiveConfig` API used for tone profile ✓
