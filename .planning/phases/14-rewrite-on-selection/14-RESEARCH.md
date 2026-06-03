# Phase 14: Rewrite on Selection — Research

**Researched:** 2026-06-03
**Phase:** 14 — Rewrite on Selection

---

## 1. Accessing Selection via Accessibility APIs

In macOS, selected text and its location can be extracted from the active application using the Accessibility API (`AXUIElement`). 

### Core Attributes
- **`kAXSelectedTextAttribute`** (`"AXSelectedText"`): Directly returns the string of the currently selected text.
- **`kAXSelectedTextRangeAttribute`** (`"AXSelectedTextRange"`): Returns the `CFRange` of the selection within the text field.
- **`kAXBoundsForRangeParameterizedAttribute`** (`"AXBoundsForRange"`): Returns the screen coordinates (`CGRect`) of the specified range.

### Verification of Feasibility
Our existing `AccessibilityMonitor.swift` already implements `getCurrentCaretRect()` and fallback paths that query these attributes.
To retrieve the selected text, we can perform:
```swift
private func getFocusedElement() -> AXUIElement? {
    let systemWideElement = AXUIElementCreateSystemWide()
    var focusedElement: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
    guard err == .success, let element = focusedElement else { return nil }
    return (element as! AXUIElement)
}

func getSelectedText() -> String? {
    guard let axElement = getFocusedElement() else { return nil }
    var selectedTextRef: CFTypeRef?
    if AXUIElementCopyAttributeValue(axElement, kAXSelectedTextAttribute as CFString, &selectedTextRef) == .success,
       let selectedText = selectedTextRef as? String {
        return selectedText
    }
    return nil
}
```

---

## 2. Keyboard Interception (Option + R)

To trigger the rewrite, we will intercept the global shortcut **Option + R** (⌥R) in `AccessibilityMonitor`'s CGEvent tap.

### Virtual Key Code
- The virtual key code for **R** on QWERTY keyboards is `15`.
- The option key modifier is represented by `CGEventFlags.maskAlternate`.

### Event Handling Flow in Event Tap:
```swift
let flags = event.flags
let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

if keyCode == 15 && flags.contains(.maskAlternate) {
    print("[TypeFlow] Option + R pressed — Triggering Rewrite on Selection")
    
    // Call CompletionManager to handle rewrite
    DispatchQueue.main.async {
        CompletionManager.shared.triggerRewrite()
    }
    
    // Return nil to consume the event (preventing typing '®' in target application)
    return nil
}
```

---

## 3. LLM Prompt Engineering for Rewriting

Unlike typing completion, rewriting is a single-turn instruction-following task. Therefore, we do not require the KV-cache optimization. A fresh context call to the local LLM is cleaner and avoids overlap-stripping logic.

### Prompt Builder addition:
```swift
func buildRewritePrompt(selectedText: String, systemInstructions: String, toneName: String) -> String {
    var prompt = ""
    prompt += "You are a writing assistant. Rewrite the following text to improve clarity, flow, and vocabulary while matching a \(toneName) tone.\n"
    prompt += "Instructions: \(systemInstructions)\n"
    prompt += "Do not write any intro, notes, explanations, or quotes. Output ONLY the rewritten text.\n\n"
    prompt += "[Text to Rewrite]:\n\(selectedText)\n\n"
    prompt += "<completion>"
    return prompt
}
```

### LLMEngine addition:
```swift
func generateRewrite(selectedText: String, toneProfile: ToneProfile) async -> String {
    await loadModelIfNeeded()
    guard let container = modelContainer, checkMemoryStatus() else { return "" }
    
    do {
        let result = try await container.perform { modelContext -> String in
            let prompt = PromptBuilder.shared.buildRewritePrompt(selectedText: selectedText, systemInstructions: toneProfile.systemInstructions, toneName: toneProfile.name)
            let input = UserInput(prompt: prompt)
            let prepared = try await modelContext.processor.prepare(input: input)
            
            // Limit maxTokens based on selection size
            let maxTokens = max(100, selectedText.count / 2)
            let params = GenerateParameters(maxTokens: maxTokens, temperature: Float(toneProfile.temperature))
            
            let stream = try MLXLMCommon.generate(
                input: prepared.input,
                cache: modelContext.model.newCache(parameters: nil),
                parameters: params,
                context: modelContext
            )
            
            var outputText = ""
            for await generation in stream {
                if case .chunk(let text) = generation {
                    outputText += text
                    if outputText.contains("</completion>") { break }
                }
            }
            return outputText
        }
        
        MLX.Memory.clearCache()
        
        var cleanResult = result
        if let range = cleanResult.range(of: "</completion>") {
            cleanResult = String(cleanResult[..<range.lowerBound])
        }
        return cleanResult.trimmingCharacters(in: .whitespacesAndNewlines)
    } catch {
        print("[TypeFlow-Debug] LLMEngine rewrite error: \(error)")
        return ""
    }
}
```

---

## 4. UI Design Contract & Premium Styling

To differentiate a rewrite suggestion from auto-completions, we will style the floating overlay window with an active, premium visual indicator.

### CompletionModel updates:
```swift
class CompletionModel: ObservableObject {
    @Published var text: String = ""
    @Published var isSpellCorrection: Bool = false
    @Published var isRewrite: Bool = false
    @Published var isLoading: Bool = false
}
```

### Overlay Design:
Instead of standard gray/orange text, rewrite suggestions will feature:
- A gradient-bordered pill badge showing `REWRITE ⌥R`
- A subtle teal/indigo gradient background
- Text showing the rewrite result
- A small helper instruction hint: `Tab to Replace • Esc to Cancel`

```swift
struct CompletionOverlayView: View {
    @ObservedObject var model: CompletionModel
    
    var body: some View {
        if model.text.isEmpty && !model.isLoading {
            Color.clear
        } else {
            HStack(spacing: 6) {
                if model.isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                } else if model.isRewrite {
                    Text("REWRITE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            LinearGradient(
                                colors: [Color.teal, Color.blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .cornerRadius(3)
                }
                
                Text(model.isLoading ? "Rewriting selection..." : model.text)
                    .foregroundColor(model.isRewrite ? Color.primary : (model.isSpellCorrection ? Color.orange : Color.secondary))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(NSColor.windowBackgroundColor).opacity(0.95))
                    .shadow(color: Color.black.opacity(0.15), radius: 4, y: 2)
            )
            .font(.system(size: 13, weight: .regular))
        }
    }
}
```

---

## 5. Text Insertion & Replacement Flow

1. **Interception**: Event tap intercepts `Option + R` and calls `CompletionManager.shared.triggerRewrite()`.
2. **Text Capture**: `CompletionManager` queries the active element's selection. If none, it does nothing.
3. **Spinner**: Set `model.isLoading = true` and `model.isRewrite = true`, then position the overlay window right next to the selection bounding box.
4. **Generation**: Call `LLMEngine.shared.generateRewrite(...)`.
5. **Display**: Update the overlay with the generated text. `model.isLoading = false`.
6. **Acceptance**: When the user presses `Tab`:
   - `CompletionManager.shared.handleTabPressed()` is triggered.
   - If `activeRewrite` is active, it calls `TextInjector.shared.inject(text: rewrittenText)`.
   - On macOS, inserting text when a selection is active naturally overwrites the selection.
   - Clear completion states.
7. **Cancellation**: If the user presses `Escape` or continues typing, the completion is cleared, hiding the overlay.

---

## Validation Architecture

### Automated Verification
- `xcodebuild` compiles without errors.
- Target keycode `15` and modifier `maskAlternate` successfully capture Option+R.
- `LLMEngine.generateRewrite` returns non-empty result and frees MLX memory.

### Manual Verification
- Select a word or sentence in TextEdit.
- Press `Option+R`. Verify that the selection is not replaced by the `®` character (proves event tap consumed it).
- Verify the overlay window appears next to the selection displaying a spinner saying "Rewriting selection...".
- Verify that the rewritten suggestion replaces the spinner once LLM completes.
- Press `Tab` and verify that the selection is cleanly replaced with the suggestion.
- Select another phrase, press `Option+R`, type a character, and verify the overlay disappears immediately.

---

## RESEARCH COMPLETE
