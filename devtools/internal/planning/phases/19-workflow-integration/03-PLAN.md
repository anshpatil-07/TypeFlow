---
wave: 3
depends_on: [2]
files_modified:
  - TypeFlow/Intents/TypeFlowRewriteIntent.swift
  - TypeFlow/TypeFlowApp.swift
autonomous: true
---

# Phase 19, Wave 3: Apple Shortcuts Integration

## Objective
Implement the `AppIntents` framework to fix the `NSCocoaErrorDomain Code=4097` errors and expose scripting to Apple Shortcuts.

## Tasks

<task>
<id>1</id>
<title>Implement AppIntents Framework</title>
<read_first>
- TypeFlow/Services/LLMEngine.swift
</read_first>
<action>
1. Create `TypeFlow/Intents/TypeFlowRewriteIntent.swift` (create the `Intents` directory).
2. Import `AppIntents`.
3. Create a struct `TypeFlowRewriteIntent: AppIntent`.
4. Define properties like `title: LocalizedStringResource = "Rewrite with TypeFlow"`.
5. Add an `@Parameter(title: "Text to rewrite") var text: String` property.
6. Implement the `func perform() async throws -> some IntentResult & ReturnsValue<String>` method.
7. This method should invoke the LLM or Rewrite logic on `text` and return the modified string.
</action>
<acceptance_criteria>
- `TypeFlowRewriteIntent.swift` exists, imports `AppIntents`, and conforms to `AppIntent`.
- The intent exposes an input parameter for text and returns a string result.
</acceptance_criteria>
</task>

<task>
<id>2</id>
<title>Register App Shortcuts Provider</title>
<read_first>
- TypeFlow/Intents/TypeFlowRewriteIntent.swift
</read_first>
<action>
1. In `TypeFlow/Intents/TypeFlowRewriteIntent.swift` (or a separate `TypeFlowShortcuts.swift`), create a struct conforming to `AppShortcutsProvider`.
2. Define `static var appShortcuts: [AppShortcut]` returning at least one shortcut wrapping `TypeFlowRewriteIntent`.
3. Call `TypeFlowShortcuts.updateAppShortcutParameters()` in `TypeFlowApp.swift` on application initialization (or via `init()` block) to ensure they are registered with macOS.
</action>
<acceptance_criteria>
- An `AppShortcutsProvider` is defined.
- It is updated/registered during app launch.
- The `NSCocoaErrorDomain Code=4097` regarding `com.apple.linkd.autoShortcut` will be resolved by having proper AppIntents integration.
</acceptance_criteria>
</task>

## Verification
<must_haves>
- The app compiles with the `AppIntents` framework.
- `TypeFlowRewriteIntent` correctly handles text input and returns output.
- `com.apple.linkd.autoShortcut` errors are no longer thrown on startup.
</must_haves>
