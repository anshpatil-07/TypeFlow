---
status: complete
phase: 19-workflow-integration
source: [01-SUMMARY.md, 02-SUMMARY.md, 03-SUMMARY.md]
started: 2026-06-07T10:19:00Z
updated: 2026-06-07T10:19:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Cold Start Smoke Test
expected: Kill any running TypeFlow instance. Start the application from scratch. The app boots without the `NSCocoaErrorDomain Code=4097 com.apple.linkd.autoShortcut` error in the logs, and basic text completion still functions.
result: issue
reported: "fail. The app still throws the exact same NSCocoaErrorDomain Code=4097 "connection to service named com.apple.linkd.autoShortcut" errors on startup, followed by a new error: Failed to connect to linkd to request update AppShortcut parameters, error: Couldn’t communicate with a helper application."
severity: blocker

### 2. Clipboard Context Injection
expected: Copy some text to your clipboard (e.g., a URL or a name). Type a trigger phrase like "here is the link: " in a text field. The suggested inline AI completion should incorporate the text you just copied.
result: issue
reported: "fail. The clipboard context injection failed because ClipboardMonitor is not running. The Issue: The ClipboardMonitor.shared.start() call was removed from AppDelegate during a previous build fix and was never re-added."
severity: blocker

### 3. macOS Services Menu - Rewrite
expected: Select text in any standard macOS app (e.g., TextEdit). Right-click, go to Services, and choose "Rewrite with TypeFlow". The selected text should be replaced with an AI-rewritten version.
result: issue
reported: "fail. The 'Rewrite with TypeFlow' and 'Expand with TypeFlow' options do not appear in the macOS right-click Services menu, even after flushing the pbs cache. The Issue: The NSServices dictionary is either missing or incorrectly configured in the Info.plist..."
severity: major

### 4. macOS Services Menu - Expand
expected: Select text in any standard macOS app. Right-click, go to Services, and choose "Expand with TypeFlow". The selected text should be expanded with AI-generated continuation text.
result: issue
reported: "fail. The 'Expand with TypeFlow' (and 'Rewrite') options are completely missing from the macOS Services menu, even after a system cache flush. The Issue: The NSServices dictionary in Info.plist is either missing, improperly structured, or the system isn't registering the services."
severity: major

### 5. Apple Shortcuts Action
expected: Open the Apple Shortcuts app. Create a new shortcut and search for the action "Rewrite with TypeFlow". It should appear as an available action that accepts text input.
result: pass

## Summary

total: 5
passed: 1
issues: 4
pending: 0
skipped: 0

## Gaps

- truth: "Kill any running TypeFlow instance. Start the application from scratch. The app boots without the `NSCocoaErrorDomain Code=4097 com.apple.linkd.autoShortcut` error in the logs, and basic text completion still functions."
  status: failed
  reason: "User reported: fail. The app still throws the exact same NSCocoaErrorDomain Code=4097..."
  severity: blocker
  test: 1
  root_cause: "Calling AppShortcuts update synchronously during applicationDidFinishLaunching causes a race condition with the macOS linkd daemon, crashing the XPC connection."
  artifacts:
    - path: "TypeFlow/AppDelegate.swift"
      issue: "Synchronous call blocking main thread during app launch"
  missing:
    - "Wrap TypeFlowShortcuts.updateAppShortcutParameters() in an asynchronous Task"

- truth: "Copy some text to your clipboard (e.g., a URL or a name). Type a trigger phrase like 'here is the link: ' in a text field. The suggested inline AI completion should incorporate the text you just copied."
  status: failed
  reason: "User reported: fail. The clipboard context injection failed because ClipboardMonitor is not running..."
  severity: blocker
  test: 2
  root_cause: "ClipboardMonitor.shared.start() missing or not executing properly. PromptBuilder fails to trigger due to trailing spaces."
  artifacts:
    - path: "TypeFlow/AppDelegate.swift"
      issue: "ClipboardMonitor start might be missing"
    - path: "TypeFlow/Services/PromptBuilder.swift"
      issue: "Trailing space causes hasSuffix to fail"
  missing:
    - "Verify/Add ClipboardMonitor.shared.start() to AppDelegate"
    - "Trim whitespaces from textBeforeCaret.lowercased() in PromptBuilder"

- truth: "Select text in any standard macOS app (e.g., TextEdit). Right-click, go to Services, and choose 'Rewrite with TypeFlow'. The selected text should be replaced with an AI-rewritten version."
  status: failed
  reason: "User reported: fail. The 'Rewrite with TypeFlow' and 'Expand with TypeFlow' options do not appear in the macOS right-click Services menu..."
  severity: major
  test: 3
  root_cause: "NSServices dictionary missing from Info.plist (xcodegen overrides it). TypeFlowServicesProvider method signatures lack Optionals."
  artifacts:
    - path: "project.yml"
      issue: "Missing NSServices array in info properties"
    - path: "TypeFlow/Services/NSServicesProvider.swift"
      issue: "Incorrect Objective-C signatures"
  missing:
    - "Add NSServices array to project.yml info properties"
    - "Update rewriteText and expandText signatures to exactly match Obj-C requirements"

- truth: "Select text in any standard macOS app. Right-click, go to Services, and choose 'Expand with TypeFlow'. The selected text should be expanded with AI-generated continuation text."
  status: failed
  reason: "User reported: fail. The 'Expand with TypeFlow' (and 'Rewrite') options are completely missing from the macOS Services menu..."
  severity: major
  test: 4
  root_cause: "macOS needs NSUpdateDynamicServices() called to register services without reboot."
  artifacts:
    - path: "TypeFlow/AppDelegate.swift"
      issue: "Missing NSUpdateDynamicServices() call"
  missing:
    - "Call NSUpdateDynamicServices() immediately after setting NSApp.servicesProvider"

