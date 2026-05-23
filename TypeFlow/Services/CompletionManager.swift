import Cocoa

class CompletionManager: @unchecked Sendable {
    static let shared = CompletionManager()
    
    var currentCompletion: String?
    weak var accessibilityMonitor: AccessibilityMonitor?
    weak var overlayWindowController: OverlayWindowController?
    
    private var debounceTimer: Timer?
    private var currentGenerationTask: Task<Void, Never>?
    
    private init() {}
    
    func setup(accessibilityMonitor: AccessibilityMonitor, overlayWindowController: OverlayWindowController) {
        self.accessibilityMonitor = accessibilityMonitor
        self.overlayWindowController = overlayWindowController
    }
    
    func onTextChanged() {
        print("[TypeFlow-Debug] onTextChanged called")
        
        // Clear existing completion immediately when user types
        clearCompletion()
        
        if let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
            if SettingsManager.shared.isAppExcluded(bundleId: bundleId) {
                clearCompletion()
                return
            }
        }
        
        // Debounce generation
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
            print("[TypeFlow-Debug] Debounce timer fired!")
            self?.triggerGeneration()
        }
    }
    
    private func triggerGeneration() {
        print("[TypeFlow-Debug] triggerGeneration started. Cancelling any previous inflight task...")
        currentGenerationTask?.cancel()
        currentGenerationTask = nil
        
        let activeLine = accessibilityMonitor?.getTextBeforeCaret() ?? ""
        
        let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        let effectiveConfig = SettingsManager.shared.getEffectiveConfig(for: bundleId)
        
        if !effectiveConfig.isEnabled {
            return
        }
        
        // Snippets check
        let snippets = SettingsManager.shared.getSnippets()
        for (key, value) in snippets {
            if activeLine.hasSuffix(key) {
                DispatchQueue.main.async {
                    self.currentCompletion = value
                    self.overlayWindowController?.updateText(value)
                }
                return
            }
        }
        
        var aggregatedContext = ContextAggregator.shared.gatherContext(activeLine: activeLine)
        let fullText = accessibilityMonitor?.getFullFieldText()
        
        aggregatedContext = AggregatedContext(
            clipboardText: aggregatedContext.clipboardText,
            screenText: aggregatedContext.screenText,
            fullFieldText: fullText,
            activeLineText: aggregatedContext.activeLineText
        )
        
        let prompt = PromptBuilder.shared.buildPrompt(context: aggregatedContext, tone: effectiveConfig.tone, instructions: effectiveConfig.instructions)
        print("[TypeFlow-Debug] Dispatching LLM generation task. Prompt sent to model:\n\(prompt)")
        
        currentGenerationTask = Task {
            let completion = await LLMEngine.shared.generateCompletion(context: prompt)
            print("[TypeFlow-Debug] Raw model output: '\(completion)'")
            if Task.isCancelled {
                print("[TypeFlow-Debug] Task was cancelled, ignoring output.")
                return 
            }
            
            var processedCompletion = completion.trimmingCharacters(in: .whitespacesAndNewlines)
            
            var overlapLength = 0
            let maxOverlap = min(activeLine.count, processedCompletion.count)
            if maxOverlap > 0 {
                for i in (1...maxOverlap).reversed() {
                    let suffix = activeLine.suffix(i)
                    let prefix = processedCompletion.prefix(i)
                    if suffix.lowercased() == prefix.lowercased() {
                        overlapLength = i
                        break
                    }
                }
            }
            if overlapLength > 0 {
                processedCompletion = String(processedCompletion.dropFirst(overlapLength))
            }
            
            print("[TypeFlow-Debug] Processed completion (after stripping \(overlapLength) chars overlap): '\(processedCompletion)'")
            
            DispatchQueue.main.async {
                self.currentCompletion = processedCompletion
                if !processedCompletion.isEmpty {
                    if let rect = self.accessibilityMonitor?.getCurrentCaretRect() {
                        print("[TypeFlow-Debug] Telling overlay to move to caret rect: \(rect)")
                        self.overlayWindowController?.moveOverlay(to: rect)
                    } else {
                        print("[TypeFlow-Debug] Caret rect was nil, NOT moving overlay!")
                    }
                    print("[TypeFlow-Debug] Telling overlay to update text to: '\(processedCompletion)'")
                    self.overlayWindowController?.updateText(processedCompletion)
                } else {
                    print("[TypeFlow-Debug] Processed completion was empty, telling overlay to hide (empty string).")
                    self.overlayWindowController?.updateText("")
                }
            }
        }
    }
    
    func handleTabPressed() -> Bool {
        if let completion = currentCompletion, !completion.isEmpty {
            // Inject the text
            TextInjector.shared.inject(text: completion)
            clearCompletion()
            return true // We handled it
        }
        return false // Let the event pass through
    }
    
    func clearCompletion() {
        currentCompletion = nil
        overlayWindowController?.updateText("")
    }
}
