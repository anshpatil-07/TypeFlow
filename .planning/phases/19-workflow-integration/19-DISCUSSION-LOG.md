# Phase 19 Discussion Log

**Date:** 2026-06-07

## Q1: Which areas do you want to discuss for Workflow Integration?
**Options presented:**
- Target Applications — Which apps should be optimized first? (IDEs, writing apps, browsers, or terminal?)
- Specialized Modes — Should it behave differently in IDEs (code) vs writing apps (prose)?
- Integration Depth — Do we need custom AppleScripts/Accessibility overrides to extract better context from stubborn apps?
- Activation Scope — On by default everywhere, or only active in a whitelist of approved apps?

**User Response:**
A1: Core Architectural Requirements for Phase 19 (Override default assumptions):

1. The "Rolling Context" Clipboard:
Action: Create a background ClipboardMonitor that polls or listens to NSPasteboard.general.changeCount.
Action: Silently maintain a rolling, in-memory array of the last 3 unique text items copied to the clipboard (URLs, emails, code snippets).
Constraint: Limit stored items to 500 characters each to prevent memory bloat.

2. Clipboard Context Injection:
Action: In PromptBuilder, if the textBeforeCaret ends with clipboard-seeking trigger phrases (e.g., "Here is the link: ", "my email is ", "the code is "), append the ClipboardMonitor's 3-item array to the system prompt context so the AI can seamlessly auto-fill the pasted value.

3. macOS Native "Services" Context Menu:
Action: Implement an NSServicesProvider class.
Action: Update the Info.plist with the NSServices array to expose "Rewrite with TypeFlow" and "Expand with TypeFlow" to the system-wide right-click context menu.

4. Apple Shortcuts & AppIntents Fix:
The Issue: The app currently throws NSCocoaErrorDomain Code=4097 regarding com.apple.linkd.autoShortcut on startup.
Action: Properly implement the AppIntents framework. Create a basic TypeFlowRewriteIntent to expose the rewriting engine to Apple Shortcuts, which will resolve the registry connection errors and make the app scriptable.
