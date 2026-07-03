---
plan: 19-03
phase: 19-workflow-integration
status: complete
completed: 2026-06-07
---

# Summary: Phase 19, Plan 03 — Apple Shortcuts Integration

## What Was Built

- **`TypeFlow/Intents/TypeFlowRewriteIntent.swift`** — Contains three declarations:
  1. `TypeFlowRewriteIntent: AppIntent` — a Shortcuts-compatible intent that rewrites a user-provided text string using the active tone profile via `LLMEngine.generateRewrite`.
  2. `TypeFlowIntentError` — error enum conforming to `CustomLocalizedStringResourceConvertible` for user-readable error messages.
  3. `TypeFlowShortcuts: AppShortcutsProvider` — registers the intent with Shortcuts phrases ("Rewrite with TypeFlow", "Rewrite this text with TypeFlow"). This is the critical fix: the absence of an `AppShortcutsProvider` was the root cause of the `NSCocoaErrorDomain Code=4097 com.apple.linkd.autoShortcut` startup errors.
- **`AppDelegate.swift`** — Added `TypeFlowShortcuts.updateAppShortcutParameters()` call on launch to register the intents with the system.

## Key Files

### Created
- `TypeFlow/Intents/TypeFlowRewriteIntent.swift`

### Modified
- `TypeFlow/AppDelegate.swift` — AppShortcuts registration

## Self-Check: PASSED
- `TypeFlowRewriteIntent` conforms to `AppIntent` with correct `perform()` signature ✓
- `TypeFlowShortcuts` conforms to `AppShortcutsProvider` with `appShortcuts` property ✓
- `updateAppShortcutParameters()` called on app launch ✓
- `NSCocoaErrorDomain Code=4097` root cause (missing AppShortcutsProvider) resolved ✓
