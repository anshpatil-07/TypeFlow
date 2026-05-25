import Cocoa

class CompletionManager: @unchecked Sendable {
    static let shared = CompletionManager()
    
    var currentCompletion: String?
    weak var accessibilityMonitor: AccessibilityMonitor?
    weak var overlayWindowController: OverlayWindowController?
    
    private var debounceTimer: Timer?
    private var currentGenerationTask: Task<Void, Never>?
    
    private var pendingCompletionRequest: String?
    
    private init() {
        NotificationCenter.default.addObserver(
            forName: Notification.Name("TypeFlowModelLoadingStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            if let isLoading = notification.object as? Bool, !isLoading {
                if let pending = self.pendingCompletionRequest {
                    print("[TypeFlow-Debug] Model finished loading. Firing pending completion request: '\(pending)'")
                    self.pendingCompletionRequest = nil
                    self.triggerGeneration(with: pending)
                }
            }
        }
    }
    
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
    
    private func triggerGeneration(with text: String? = nil) {
        print("[TypeFlow-Debug] triggerGeneration started. Cancelling any previous inflight task...")
        currentGenerationTask?.cancel()
        currentGenerationTask = nil
        
        let activeLine = text ?? accessibilityMonitor?.getTextBeforeCaret() ?? ""
        guard !activeLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("[TypeFlow-Debug] Active line is empty, skipping generation.")
            return
        }
        
        if !LLMEngine.shared.isModelReady {
            print("[TypeFlow-Debug] Model is not ready yet. Queuing request: '\(activeLine)'")
            pendingCompletionRequest = activeLine
            return
        }
        
        let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        let effectiveConfig = SettingsManager.shared.getEffectiveConfig(for: bundleId)
        
        if !effectiveConfig.isEnabled {
            print("[TypeFlow-Debug] Completions disabled for \(bundleId), skipping.")
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
        
        print("[TypeFlow-Debug] Dispatching LLM generation for: '\(activeLine)'")
        
        currentGenerationTask = Task {
            let completion = await LLMEngine.shared.generateCompletion(
                textBeforeCaret: activeLine,
                tone: effectiveConfig.tone,
                customInstructions: effectiveConfig.instructions
            )
            print("[TypeFlow-Debug] Raw model output: '\(completion)'")
            if Task.isCancelled {
                print("[TypeFlow-Debug] Task was cancelled, ignoring output.")
                return 
            }
            
            var processedCompletion = completion.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Strip any echoed prefix overlap between the end of activeLine and start of completion
            let maxOverlap = min(activeLine.count, processedCompletion.count)
            var overlapLength = 0
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
                processedCompletion = processedCompletion.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            // Strip markdown formatting
            processedCompletion = self.stripMarkdown(processedCompletion)
            
            print("[TypeFlow-Debug] Processed completion (after stripping \(overlapLength) chars overlap & markdown): '\(processedCompletion)'")
            
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
                    print("[TypeFlow-Debug] Processed completion was empty, hiding overlay.")
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
    
    func stripMarkdown(_ text: String) -> String {
        var result = text
        // Remove bold/italic markup: **, *, __, _
        result = result.replacingOccurrences(of: "**", with: "")
        result = result.replacingOccurrences(of: "__", with: "")
        result = result.replacingOccurrences(of: "*", with: "")
        result = result.replacingOccurrences(of: "_", with: "")
        result = result.replacingOccurrences(of: "`", with: "")
        
        // Remove header markers like #, ##
        result = result.replacingOccurrences(of: "#", with: "")
        
        // Trim leading bullet symbols or markdown list symbols: e.g. "- ", "+ ", "* "
        let pattern = "^(\\s*[-+*]\\s+)+"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(location: 0, length: result.utf16.count)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
