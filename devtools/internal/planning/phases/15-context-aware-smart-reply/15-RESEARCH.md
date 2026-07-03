# Phase 15: Context-Aware Smart Reply - Research

## Objective
Research the technical approach and dependencies for implementing Context-Aware Smart Reply (Phase 15) before planning.

## Findings

### 1. Trigger Mechanism (Global Shortcut)
- **Current State**: `SettingsManager` stores `rewriteShortcut` and `acceptShortcut`. `AccessibilityMonitor` uses `matchesRewriteShortcut` inside the global `CGEvent` tap to intercept the shortcut and call `CompletionManager.shared.triggerRewrite()`.
- **Approach**: 
  - Add `@AppStorage("smartReplyShortcut") var smartReplyShortcut: String = "Command+Shift+R"` to `SettingsManager`.
  - Add `matchesSmartReplyShortcut(event:)` to `AccessibilityMonitor`.
  - On match, intercept the event and call `CompletionManager.shared.triggerSmartReply()`.

### 2. Context Extraction (Accessibility + Vision OCR)
- **Current State**: 
  - `ScreenContextManager.shared.latestScreenText` holds the latest periodic OCR text (max 2000 chars, updates every 5s).
  - `AccessibilityMonitor` has `getTextBeforeCaret()` and `getFullFieldText()`.
- **Approach**:
  - In `triggerSmartReply()`, fetch both `ScreenContextManager.shared.latestScreenText` and `accessibilityMonitor.getFullFieldText()` (or selection).
  - Combine these into a single context prompt for the LLM.

### 3. LLM Generation (3 Options)
- **Current State**: `LLMEngine` has `generateCompletion()` and `generateRewrite()`.
- **Approach**:
  - Add `generateSmartReplies(context: String) async -> [String]` to `LLMEngine`.
  - Prompt the LLM to act as a Smart Reply generator, using the combined text as context.
  - Instruct the LLM to output exactly 3 options (e.g. Professional, Casual, Concise), separated by a specific delimiter (like `|||`) or as a JSON array, to easily parse them into an array of strings.

### 4. UI Presentation (Popover Reuse)
- **Current State**: `OverlayWindowController` and `CompletionOverlayView` handle the popover. `CompletionModel` tracks `isRewrite` and `text`. It displays `RewriteModeBarView` with 3 buttons when generating.
- **Approach**:
  - Extend `CompletionModel` with `isSmartReply: Bool` and `smartReplyOptions: [String]`.
  - Add a `SmartReplyOptionsView` in `OverlayWindowController.swift` that maps the `smartReplyOptions` array to 3 clickable buttons.
  - When a button is clicked, call `CompletionManager.shared.acceptSmartReply(text: option)`.
  - Update `repositionWindow()` to handle the height/width of the Smart Reply options list.

### 5. Injection (Accepting Reply)
- **Current State**: `handleTabPressed` injects text. Rewrite mode uses a 50ms delay after hiding the overlay.
- **Approach**:
  - In `acceptSmartReply(text:)`, hide the overlay, clear buffers, delay 50ms, and call `TextInjector.shared.inject(text: text)`.

## Validation Architecture
- **Shortcut interception**: Verify `Command+Shift+R` triggers the Smart Reply state.
- **Context combination**: Verify `LLMEngine.generateSmartReplies` receives both OCR text and Accessibility text.
- **UI Rendering**: Verify the popover displays 3 options when LLM returns them.
- **Injection**: Verify clicking an option hides the popover and injects the selected text into the active field.

## Conclusion
The architecture is fully ready to support this feature by duplicating the patterns established in Phase 14 (Rewrite mode). No external dependencies or significant structural changes are required.
