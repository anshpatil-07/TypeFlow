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
        currentGenerationTask?.cancel()
        currentGenerationTask = nil
        
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
            self?.triggerGeneration()
        }
    }
    
    private func triggerGeneration() {
        print("[TypeFlow] triggerGeneration called")
        let activeLine = accessibilityMonitor?.getTextBeforeCaret() ?? ""
        print("[TypeFlow] Active line: \(activeLine)")
        
        let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        let effectiveConfig = SettingsManager.shared.getEffectiveConfig(for: bundleId)
        
        if !effectiveConfig.isEnabled {
            print("[TypeFlow] App \(bundleId) is excluded")
            return
        }
        
        // Snippets check
        let snippets = SettingsManager.shared.getSnippets()
        for (key, value) in snippets {
            if activeLine.hasSuffix(key) {
                print("[TypeFlow] Snippet match for key: \(key)")
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
        print("[TypeFlow] Dispatching LLM generation task...")
        
        currentGenerationTask = Task {
            let completion = await LLMEngine.shared.generateCompletion(context: prompt)
            if Task.isCancelled { return }
            print("[TypeFlow] Got completion: \(completion)")
            
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
            
            DispatchQueue.main.async {
                self.currentCompletion = processedCompletion
                if !processedCompletion.isEmpty {
                    if let rect = self.accessibilityMonitor?.getCurrentCaretRect() {
                        self.overlayWindowController?.moveOverlay(to: rect)
                    }
                    self.overlayWindowController?.updateText(processedCompletion)
                } else {
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
