# Phase 19: Workflow Integration - Context

**Gathered:** 2026-06-07
**Status:** Ready for planning

<domain>
## Phase Boundary

Integrating TypeFlow into native macOS workflows via system services, Shortcuts, and rolling clipboard context to expand accessibility and intelligence beyond inline typing.
</domain>

<decisions>
## Implementation Decisions

### Clipboard Integration
- **D-01 (Rolling Context):** Create a background `ClipboardMonitor` that polls or listens to `NSPasteboard.general.changeCount`. Silently maintain a rolling, in-memory array of the last 3 unique text items copied to the clipboard (URLs, emails, code snippets). Limit stored items to 500 characters each to prevent memory bloat.
- **D-02 (Context Injection):** In `PromptBuilder`, if the `textBeforeCaret` ends with clipboard-seeking trigger phrases (e.g., "Here is the link: ", "my email is ", "the code is "), append the `ClipboardMonitor`'s 3-item array to the system prompt context so the AI can seamlessly auto-fill the pasted value.

### macOS Native Services
- **D-03 (Services Menu):** Implement an `NSServicesProvider` class. Update the `Info.plist` with the `NSServices` array to expose "Rewrite with TypeFlow" and "Expand with TypeFlow" to the system-wide right-click context menu.

### Apple Shortcuts Integration
- **D-04 (AppIntents Fix):** Properly implement the AppIntents framework to fix the `NSCocoaErrorDomain Code=4097` error regarding `com.apple.linkd.autoShortcut` on startup. Create a basic `TypeFlowRewriteIntent` to expose the rewriting engine to Apple Shortcuts, resolving the registry connection errors and making the app scriptable.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Architecture
- `.planning/PROJECT.md` — Core constraints and values

### Technical References
*(Note: Refer to macOS documentation for AppIntents and NSServicesProvider during implementation)*
</canonical_refs>
