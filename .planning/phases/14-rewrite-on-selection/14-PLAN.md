# Phase 14 Plan: Rewrite on Selection

**Phase:** 14 — Rewrite on Selection  
**Goal:** Intercept Option+R, extract the active application's selected text using Accessibility APIs, query the local LLM to rewrite it in the active tone profile, and display the result in a premium SwiftUI overlay allowing the user to press Tab to replace the selection.  
**Depends on:** Phase 13  

---

## Proposed Changes

### Wave 1: Services and Engine Logic

#### [MODIFY] [PromptBuilder.swift](file:///Users/anshalankarpatil/Documents/cotyper/TypeFlow/Services/PromptBuilder.swift)
Add a method `buildRewritePrompt` to generate rewrite instructions for the LLM.

- **Objective**: Generate specialized system instructions and formatting for selection rewrite.
- **Dependencies**: None.
- **Task**:
  ```xml
  <task id="prompt-builder-rewrite">
    <read_first>
      - TypeFlow/Services/PromptBuilder.swift
    </read_first>
    <action>
      Add buildRewritePrompt method to PromptBuilder class:
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
    </action>
    <acceptance_criteria>
      - PromptBuilder.swift contains function `buildRewritePrompt(selectedText:systemInstructions:toneName:)`
    </acceptance_criteria>
  </task>
  ```

#### [MODIFY] [LLMEngine.swift](file:///Users/anshalankarpatil/Documents/cotyper/TypeFlow/Services/LLMEngine.swift)
Add `generateRewrite` method to `LLMEngine` to execute single-turn inference.

- **Objective**: Implement MLX inference for rewriting without KV-cache prefill.
- **Dependencies**: `PromptBuilder.swift` change.
- **Task**:
  ```xml
  <task id="llm-engine-rewrite">
    <read_first>
      - TypeFlow/Services/LLMEngine.swift
      - TypeFlow/Services/PromptBuilder.swift
    </read_first>
    <action>
      Add generateRewrite method to LLMEngine class:
      ```swift
      func generateRewrite(selectedText: String, toneProfile: ToneProfile) async -> String {
          await loadModelIfNeeded()
          guard let container = modelContainer else {
              print("[TypeFlow-Debug] LLMEngine: modelContainer is nil for rewrite")
              return ""
          }
          guard checkMemoryStatus() else {
              print("[TypeFlow-Debug] LLMEngine: Low memory guard triggered for rewrite")
              return ""
          }
          
          do {
              let result = try await container.perform { modelContext -> String in
                  let prompt = PromptBuilder.shared.buildRewritePrompt(
                      selectedText: selectedText,
                      systemInstructions: toneProfile.systemInstructions,
                      toneName: toneProfile.name
                  )
                  let input = UserInput(prompt: prompt)
                  let prepared = try await modelContext.processor.prepare(input: input)
                  
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
                          if outputText.contains("</completion>") {
                              break
                          }
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
    </action>
    <acceptance_criteria>
      - LLMEngine.swift contains function `generateRewrite(selectedText:toneProfile:)`
    </acceptance_criteria>
  </task>
  ```

#### [MODIFY] [SettingsManager.swift](file:///Users/anshalankarpatil/Documents/cotyper/TypeFlow/Services/SettingsManager.swift)
Add customizable shortcut storage.

- **Objective**: Store shortcut preferences persistently.
- **Dependencies**: None.
- **Task**:
  ```xml
  <task id="settings-manager-rewrite-shortcut">
    <read_first>
      - TypeFlow/Services/SettingsManager.swift
    </read_first>
    <action>
      Add persistent setting property for the rewrite shortcut:
      ```swift
      @AppStorage("rewriteShortcut") var rewriteShortcut: String = "Option+R"
      ```
    </action>
    <acceptance_criteria>
      - SettingsManager.swift contains property `rewriteShortcut`
    </acceptance_criteria>
  </task>
  ```

#### [MODIFY] [SettingsView.swift](file:///Users/anshalankarpatil/Documents/cotyper/TypeFlow/UI/SettingsView.swift)
Provide selection UI for customizable rewrite shortcuts.

- **Objective**: Let user configure shortcut options.
- **Dependencies**: `SettingsManager.swift` changes.
- **Task**:
  ```xml
  <task id="settings-view-rewrite-shortcut">
    <read_first>
      - TypeFlow/UI/SettingsView.swift
    </read_first>
    <action>
      Add a Picker for shortcut options in the General tab:
      ```swift
      Picker("Rewrite Shortcut:", selection: $settings.rewriteShortcut) {
          Text("Option + R (⌥R)").tag("Option+R")
          Text("Option + E (⌥E)").tag("Option+E")
          Text("Option + W (⌥W)").tag("Option+W")
          Text("Control + R (⌃R)").tag("Control+R")
          Text("Control + E (⌃E)").tag("Control+E")
          Text("Control + W (⌃W)").tag("Control+W")
      }
      .pickerStyle(DefaultPickerStyle())
      .padding(.top)
      ```
    </action>
    <acceptance_criteria>
      - SettingsView.swift contains a Picker for `rewriteShortcut` under the General tab
    </acceptance_criteria>
  </task>
  ```

#### [MODIFY] [AccessibilityMonitor.swift](file:///Users/anshalankarpatil/Documents/cotyper/TypeFlow/Services/AccessibilityMonitor.swift)
Implement key interception for configured shortcut and selected text retrieval.

- **Objective**: Capture selection via AX and catch selected global hotkey.
- **Dependencies**: `SettingsManager.swift` changes.
- **Task**:
  ```xml
  <task id="accessibility-monitor-rewrite">
    <read_first>
      - TypeFlow/Services/AccessibilityMonitor.swift
    </read_first>
    <action>
      1. Add helper method `getSelectedText` to AccessibilityMonitor:
      ```swift
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
      2. Add helper method `matchesRewriteShortcut` to resolve dynamic setting:
      ```swift
      private func matchesRewriteShortcut(keyCode: Int64, flags: CGEventFlags) -> Bool {
          let shortcut = SettingsManager.shared.rewriteShortcut
          switch shortcut {
          case "Option+R": return keyCode == 15 && flags.contains(.maskAlternate)
          case "Option+E": return keyCode == 14 && flags.contains(.maskAlternate)
          case "Option+W": return keyCode == 13 && flags.contains(.maskAlternate)
          case "Control+R": return keyCode == 15 && flags.contains(.maskControl)
          case "Control+E": return keyCode == 14 && flags.contains(.maskControl)
          case "Control+W": return keyCode == 13 && flags.contains(.maskControl)
          default: return keyCode == 15 && flags.contains(.maskAlternate)
          }
      }
      ```
      3. Inside `start()` method, inside the event tap callback handler where key events are captured:
      ```swift
      let flags = event.flags
      let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
      
      if matchesRewriteShortcut(keyCode: keyCode, flags: flags) {
          print("[TypeFlow] Intercepted Rewrite Shortcut — triggering Rewrite selection")
          DispatchQueue.main.async {
              CompletionManager.shared.triggerRewrite()
          }
          return nil // Consume event to prevent printing characters
      }
      ```
    </action>
    <acceptance_criteria>
      - AccessibilityMonitor.swift contains functions `getSelectedText()` and `matchesRewriteShortcut(keyCode:flags:)`
      - AccessibilityMonitor.swift event tap calls `matchesRewriteShortcut` and intercepts configured hotkey
    </acceptance_criteria>
  </task>
  ```

---

### Wave 2: UI and Manager Integration

#### [MODIFY] [OverlayWindowController.swift](file:///Users/anshalankarpatil/Documents/cotyper/TypeFlow/UI/OverlayWindowController.swift)
Add loading, rewrite states, and premium visual badge styling.

- **Objective**: Differentiate rewrite states visually with loading spinner and pill badge.
- **Dependencies**: None.
- **Task**:
  ```xml
  <task id="overlay-window-rewrite">
    <read_first>
      - TypeFlow/UI/OverlayWindowController.swift
    </read_first>
    <action>
      1. Add `@Published var isRewrite: Bool = false` and `@Published var isLoading: Bool = false` to `CompletionModel`.
      2. Update `CompletionOverlayView` body to layout rewrite elements:
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
      3. Update signature of `updateText` in `OverlayWindowController`:
      ```swift
      func updateText(_ newText: String, isSpellCorrection: Bool = false, isRewrite: Bool = false, isLoading: Bool = false) {
          print("[TypeFlow-Debug] OverlayWindowController updateText received: '\(newText)', isSpellCorrection: \(isSpellCorrection), isRewrite: \(isRewrite), isLoading: \(isLoading)")
          DispatchQueue.main.async { [weak self] in
              guard let self = self else { return }
              self.completionModel.isSpellCorrection = isSpellCorrection
              self.completionModel.isRewrite = isRewrite
              self.completionModel.isLoading = isLoading
              self.completionModel.text = newText
              if newText.isEmpty && !isLoading {
                  print("[TypeFlow-Debug] Hiding overlay window")
                  self.overlayWindow.orderOut(nil)
              } else {
                  print("[TypeFlow-Debug] Showing overlay window")
                  self.repositionWindow()
                  self.overlayWindow.orderFront(nil)
              }
          }
      }
      ```
      4. Adjust `repositionWindow()` width calculation to handle loading text:
      ```swift
      let measureText = completionModel.isLoading ? "Rewriting selection..." : completionModel.text
      let size = (measureText as NSString).size(withAttributes: attributes)
      let textWidth = size.width + (completionModel.isRewrite ? 65 : 12) // Extra padding for rewrite pill badge
      ```
    </action>
    <acceptance_criteria>
      - OverlayWindowController.swift contains `@Published var isRewrite: Bool` and `@Published var isLoading: Bool` in `CompletionModel`.
      - `updateText` signature supports `isRewrite` and `isLoading` parameters.
    </acceptance_criteria>
  </task>
  ```

#### [MODIFY] [CompletionManager.swift](file:///Users/anshalankarpatil/Documents/cotyper/TypeFlow/Services/CompletionManager.swift)
Implement rewrite workflow dispatch, selection replacement, and reset/cancel triggers.

- **Objective**: Manage state machine transitions for the rewrite action.
- **Dependencies**: `LLMEngine`, `AccessibilityMonitor`, and `OverlayWindowController` updates.
- **Task**:
  ```xml
  <task id="completion-manager-rewrite">
    <read_first>
      - TypeFlow/Services/CompletionManager.swift
    </read_first>
    <action>
      1. Add state property to `CompletionManager` class:
      ```swift
      private var activeRewriteText: String?
      ```
      2. Add `triggerRewrite()` method:
      ```swift
      func triggerRewrite() {
          print("[TypeFlow-Debug] CompletionManager: triggerRewrite called")
          
          guard let selection = accessibilityMonitor?.getSelectedText(),
                !selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
              print("[TypeFlow-Debug] No selection to rewrite")
              return
          }
          
          // Cancel normal completions
          debounceTimer?.invalidate()
          debounceTimer = nil
          currentGenerationTask?.cancel()
          currentGenerationTask = nil
          
          activeSpellCorrection = nil
          activeSnippetKey = nil
          
          // Set overlay loading state
          DispatchQueue.main.async {
              if let rect = self.accessibilityMonitor?.getCurrentCaretRect() {
                  self.overlayWindowController?.moveOverlay(to: rect)
              }
              self.overlayWindowController?.updateText("", isRewrite: true, isLoading: true)
          }
          
          let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
          let effectiveConfig = SettingsManager.shared.getEffectiveConfig(for: bundleId)
          
          currentGenerationTask = Task {
              let rewritten = await LLMEngine.shared.generateRewrite(selectedText: selection, toneProfile: effectiveConfig.toneProfile)
              
              if Task.isCancelled {
                  print("[TypeFlow-Debug] Rewrite generation cancelled")
                  return
              }
              
              DispatchQueue.main.async {
                  if !rewritten.isEmpty {
                      self.currentCompletion = rewritten
                      self.activeRewriteText = selection
                      self.overlayWindowController?.updateText(rewritten, isRewrite: true, isLoading: false)
                  } else {
                      self.clearCompletion()
                  }
              }
          }
      }
      ```
      3. Update `handleTabPressed() -> Bool` to inject replacement when `activeRewriteText` is active:
      ```swift
      if let rewriteText = activeRewriteText, let completion = currentCompletion, !completion.isEmpty {
          print("[TypeFlow-Debug] Accepting rewrite: replacing selection with '\(completion)'")
          // Inject rewritten text (replacing selection)
          TextInjector.shared.inject(text: completion)
          clearCompletion()
          return true
      }
      ```
      4. Update `clearCompletion()` to reset `activeRewriteText`:
      ```swift
      activeRewriteText = nil
      // Also update updateText call in clearCompletion to pass isRewrite: false, isLoading: false
      overlayWindowController?.updateText("", isSpellCorrection: false, isRewrite: false, isLoading: false)
      ```
    </action>
    <acceptance_criteria>
      - CompletionManager.swift contains property `activeRewriteText` and method `triggerRewrite()`
      - `handleTabPressed` handles `activeRewriteText` replacement.
      - `clearCompletion` resets `activeRewriteText` and updates overlay window flags.
    </acceptance_criteria>
  </task>
  ```

---

## Verification Plan

### Automated Tests
- Command to compile/build the Xcode project:
  ```bash
  xcodebuild -project TypeFlow.xcodeproj -scheme TypeFlow clean build -sdk macosx
  ```

### Manual Verification
1. **Shortcut Interception**: Open TextEdit, type "The weather is very good today", select it, and press `Option + R`. Verify that the text is NOT replaced by the `®` symbol, confirming the event tap consumed the keystroke.
2. **Spinner & Placement**: Verify that the overlay window displays next to the selection bounds showing a spinner indicating "Rewriting selection...".
3. **LLM Inference**: Verify that the local LLM generates a rewritten version and displays it in the overlay view with the gradient "REWRITE" badge.
4. **Replacement**: Press `Tab` and verify that the selection in TextEdit is replaced by the rewritten sentence.
5. **Dismissal**: Select some text, press `Option + R` to trigger rewrite, press `Escape`, and verify the overlay closes.
6. **Typing Cancel**: Select some text, press `Option + R`, type a key, and verify the suggestion disappears immediately.
