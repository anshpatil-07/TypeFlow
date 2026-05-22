import Cocoa

class CompletionManager {
    static let shared = CompletionManager()
    
    var currentCompletion: String?
    weak var accessibilityMonitor: AccessibilityMonitor?
    weak var overlayWindowController: OverlayWindowController?
    
    private var debounceTimer: Timer?
    
    private init() {}
    
    func setup(accessibilityMonitor: AccessibilityMonitor, overlayWindowController: OverlayWindowController) {
        self.accessibilityMonitor = accessibilityMonitor
        self.overlayWindowController = overlayWindowController
    }
    
    func onTextChanged() {
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
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.triggerGeneration()
        }
    }
    
    private func triggerGeneration() {
        guard let activeLine = accessibilityMonitor?.getTextBeforeCaret() else { return }
        
        let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        let effectiveConfig = SettingsManager.shared.getEffectiveConfig(for: bundleId)
        
        if !effectiveConfig.isEnabled { return }
        
        // Snippets check
        let snippets = SettingsManager.shared.getSnippets()
        for (key, value) in snippets {
            if activeLine.hasSuffix(key) {
                // If it ends with the snippet, we can inject directly.
                // Wait, if it ends with snippet, we might want to replace it. For now, just generate the value as completion.
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
        
        Task {
            let completion = await LLMEngine.shared.generateCompletion(context: prompt)
            
            DispatchQueue.main.async {
                self.currentCompletion = completion
                self.overlayWindowController?.updateText(completion)
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
