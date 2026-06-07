---
wave: 1
depends_on: []
files_modified:
  - TypeFlow/Services/SettingsManager.swift
  - TypeFlow/Services/AccessibilityMonitor.swift
  - TypeFlow/Services/CompletionManager.swift
  - TypeFlow/Services/LLMEngine.swift
  - TypeFlow/UI/OverlayWindowController.swift
autonomous: true
---

# Phase 15: Context-Aware Smart Reply - Plan

## Objective
Implement Context-Aware Smart Reply to generate 3 reply options based on on-screen conversations by combining Accessibility API text and Vision OCR. The feature is triggered via a global shortcut and presented in a 3-option popover.

## Must Haves
- Global shortcut interception for `Command+Shift+R` to trigger smart replies without writing characters to the active field.
- Combination of Vision OCR (`latestScreenText`) and active field text to provide maximum context to the LLM.
- LLM prompt that enforces the generation of exactly 3 distinct reply options (Professional, Casual, Concise) separated by `|||`.
- Popover UI with 3 clickable options that inject the selected text and hide the overlay.

## Tasks

<task>
<read_first>
- TypeFlow/Services/SettingsManager.swift
</read_first>
<action>
Modify `TypeFlow/Services/SettingsManager.swift` to add the smart reply shortcut configuration.
Add `@AppStorage("smartReplyShortcut") var smartReplyShortcut: String = "Command+Shift+R"` directly below the existing `@AppStorage("rewriteShortcut")` declaration.
</action>
<acceptance_criteria>
`grep "smartReplyShortcut" TypeFlow/Services/SettingsManager.swift` returns the `@AppStorage` declaration with default `"Command+Shift+R"`.
</acceptance_criteria>
</task>

<task>
<read_first>
- TypeFlow/Services/AccessibilityMonitor.swift
</read_first>
<action>
Modify `TypeFlow/Services/AccessibilityMonitor.swift` to intercept the smart reply shortcut.
1. Add a new function `func matchesSmartReplyShortcut(event: CGEvent) -> Bool` below `matchesRewriteShortcut`. Implement it identically to `matchesRewriteShortcut` but use `SettingsManager.shared.smartReplyShortcut` instead of `rewriteShortcut`.
2. In the `CGEvent.tapCreate` callback inside `start()`, add a check below the `matchesRewriteShortcut` check:
```swift
if obj.matchesSmartReplyShortcut(event: event) {
    print("[TypeFlow] Intercepted Smart Reply Shortcut — triggering Smart Reply")
    DispatchQueue.main.async {
        CompletionManager.shared.triggerSmartReply()
    }
    return nil // Consume event
}
```
</action>
<acceptance_criteria>
`grep "func matchesSmartReplyShortcut" TypeFlow/Services/AccessibilityMonitor.swift` finds the new function.
`grep "CompletionManager.shared.triggerSmartReply()" TypeFlow/Services/AccessibilityMonitor.swift` finds the hook in the event tap.
</acceptance_criteria>
</task>

<task>
<read_first>
- TypeFlow/Services/LLMEngine.swift
</read_first>
<action>
Modify `TypeFlow/Services/LLMEngine.swift` to add the generation function.
Add a new method `func generateSmartReplies(contextText: String) async -> [String]`:
1. Check `!isModelReady`, returning `[]` if false.
2. Build a prompt specifically for smart replies:
```swift
let prompt = """
You are a context-aware smart reply assistant. Based on the conversation context provided below, generate exactly 3 short, distinct reply options (e.g. Professional, Casual, Concise) that the user could send in response.
Output the 3 options separated EXACTLY by the delimiter '|||' and nothing else. No formatting, no prefixes.

Context:
\(contextText)

Replies:
"""
```
3. Call the `model.generate` function with `temperature: 0.6` and `maxTokens: 150`.
4. Process the returned string by splitting it using `components(separatedBy: "|||")`. Trim whitespaces and filter out empty strings. Return the resulting array (capped to 3 elements).
</action>
<acceptance_criteria>
`grep "func generateSmartReplies" TypeFlow/Services/LLMEngine.swift` finds the function.
`grep "|||" TypeFlow/Services/LLMEngine.swift` verifies the delimiter logic is present.
</acceptance_criteria>
</task>

<task>
<read_first>
- TypeFlow/UI/OverlayWindowController.swift
</read_first>
<action>
Modify `TypeFlow/UI/OverlayWindowController.swift` to support displaying and clicking smart reply options.
1. Update `CompletionModel` to include:
```swift
@Published var isSmartReply: Bool = false
@Published var smartReplyOptions: [String] = []
```
2. Create a new SwiftUI View `SmartReplyOptionsView`:
```swift
struct SmartReplyOptionsView: View {
    let options: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Smart Replies:")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
            ForEach(options, id: \.self) { option in
                Button(action: {
                    CompletionManager.shared.acceptSmartReply(text: option)
                }) {
                    Text(option)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.blue.opacity(0.1))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.95))
                .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 2)
        )
        .focusable(false)
    }
}
```
3. Update `CompletionOverlayView` to render `SmartReplyOptionsView` when `model.isSmartReply` is true and `!model.smartReplyOptions.isEmpty`. If `model.isLoading && model.isSmartReply`, render the "Generating..." spinner similar to rewrite.
4. In `OverlayWindowController.repositionWindow()`, adjust `windowHeight` for `isSmartReply`:
```swift
let isSmartReplyList = completionModel.isSmartReply && !completionModel.smartReplyOptions.isEmpty
if isSmartReplyList {
    windowHeight = CGFloat(30 + (completionModel.smartReplyOptions.count * 32))
    windowWidth = 360
}
```
5. Add `isSmartReply: Bool = false, smartReplyOptions: [String] = []` to `updateText` signature and assign them to `completionModel`.
</action>
<acceptance_criteria>
`grep "SmartReplyOptionsView" TypeFlow/UI/OverlayWindowController.swift` finds the new view.
`grep "acceptSmartReply" TypeFlow/UI/OverlayWindowController.swift` verifies the button action calls the manager.
</acceptance_criteria>
</task>

<task>
<read_first>
- TypeFlow/Services/CompletionManager.swift
- TypeFlow/Services/ScreenContextManager.swift
- TypeFlow/UI/OverlayWindowController.swift
</read_first>
<action>
Modify `TypeFlow/Services/CompletionManager.swift` to handle smart reply logic.
1. Add `var isSmartReply: Bool { activeSmartReply }` and `private var activeSmartReply: Bool = false`.
2. Update `clearCompletion()` to set `activeSmartReply = false` and pass the extra args to `updateText`.
3. Add `func triggerSmartReply()`:
   - Cancel timers and tasks.
   - Set `activeSmartReply = true`.
   - Update overlay to "Generating..." with `isSmartReply: true`, anchoring to `accessibilityMonitor?.getCurrentCaretRect()`.
   - Start a Task to gather context: `let ocrText = ScreenContextManager.shared.latestScreenText` and `let axText = accessibilityMonitor?.getFullFieldText() ?? ""`.
   - Combine them: `let combinedContext = "Screen Text:\n\(ocrText)\n\nActive Field:\n\(axText)"`.
   - Await `LLMEngine.shared.generateSmartReplies(contextText: combinedContext)`.
   - On main thread, if options are found, call `overlayWindowController?.updateText("", isSmartReply: true, smartReplyOptions: options)`.
4. Add `func acceptSmartReply(text: String)`:
   - Hide overlay immediately using `updateText("", ...)` and call `clearCompletion()`.
   - Clear keystroke buffer.
   - Spawn a Task with `try? await Task.sleep(nanoseconds: 50_000_000)` and then `TextInjector.shared.inject(text: text)`.
</action>
<acceptance_criteria>
`grep "func triggerSmartReply()" TypeFlow/Services/CompletionManager.swift` finds the trigger method.
`grep "func acceptSmartReply" TypeFlow/Services/CompletionManager.swift` finds the injection method.
</acceptance_criteria>
</task>

## Verification
- Run the app, focus a text field in a messaging app, and press `Command+Shift+R`.
- Verify the "Generating..." popover appears at the caret.
- Verify 3 options appear in the popover after a moment.
- Click an option and verify the popover disappears and the text is injected into the text field.
