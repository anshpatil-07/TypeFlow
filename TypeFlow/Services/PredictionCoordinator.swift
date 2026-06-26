import Foundation
import Cocoa

enum KeystrokeEvaluationResult {
    case matchedAndAdvanced
    case invalidated
    case noGhostText
}

@MainActor
final class PredictionCoordinator {
    static let shared = PredictionCoordinator()
    
    weak var overlayWindowController: OverlayWindowController?
    
    private var displayedSuggestion: String?
    private var generationIDCounter: UInt64 = 0
    private var debounceTask: Task<Void, Never>?
    private var lastBufferSnapshot: String = ""
    
    private init() {
        EditorEventBus.shared.subscribe { [weak self] event in
            if Thread.isMainThread {
                self?.handleEditorEvent(event)
            } else {
                DispatchQueue.main.async {
                    self?.handleEditorEvent(event)
                }
            }
        }
        
        Task {
            await PredictionWorker.shared.setCallback { [weak self] id, result, metrics, isFinal in
                Task { @MainActor in
                    self?.handlePredictionResult(id: id, completion: result, metrics: metrics, isFinal: isFinal)
                }
            }
        }
    }
    
    weak var accessibilityMonitor: AccessibilityMonitor?
    func setup(overlayWindowController: OverlayWindowController, accessibilityMonitor: AccessibilityMonitor) {
        self.accessibilityMonitor = accessibilityMonitor
        self.overlayWindowController = overlayWindowController
    }
    
    func clearDisplayedSuggestion() {
        displayedSuggestion = nil
        CompletionManager.shared.currentCompletion = nil
        overlayWindowController?.updateText("")
    }
    
    private func handleEditorEvent(_ event: EditorEventType) {
        switch event {
        case .textChanged(let bufferSnapshot, let isPunctuation):
            let result = evaluateKeystroke(bufferFallback: bufferSnapshot)
            
            switch result {
            case .matchedAndAdvanced:
                break
            case .invalidated:
                scheduleGeneration(bufferSnapshot: bufferSnapshot, isPunctuation: isPunctuation, bypassDebounce: true)
            case .noGhostText:
                scheduleGeneration(bufferSnapshot: bufferSnapshot, isPunctuation: isPunctuation, bypassDebounce: false)
            }
            
        case .documentContextChanged:
            clearDisplayedSuggestion()
            PromptBuilder.shared.invalidateFrozenPrefix()
            Task { await PredictionWorker.shared.cancelActiveGeneration() }
            
        case .spaceOrReturnPressed(let bufferSnapshot):
            let result = evaluateKeystroke(bufferFallback: bufferSnapshot)
            if result != .matchedAndAdvanced {
                scheduleGeneration(bufferSnapshot: bufferSnapshot, isPunctuation: true, bypassDebounce: true)
            }
            
        case .selectionChanged:
            clearDisplayedSuggestion()
            debounceTask?.cancel()
            Task { await PredictionWorker.shared.cancelActiveGeneration() }
        }
    }
    
    private func evaluateKeystroke(bufferFallback: String) -> KeystrokeEvaluationResult {
        if CompletionManager.shared.isRewrite || CompletionManager.shared.isSmartReply {
            lastBufferSnapshot = bufferFallback
            return .noGhostText
        }
        
        if let ghost = displayedSuggestion, !ghost.isEmpty {
            let prev = lastBufferSnapshot
            let curr = bufferFallback
            if curr.count == prev.count + 1 && curr.hasPrefix(prev) {
                let newChar = String(curr.last!)
                let ghostFirst = String(ghost.prefix(1))
                if newChar == ghostFirst {
                    let advanced = String(ghost.dropFirst())
                    if advanced.isEmpty {
                        clearDisplayedSuggestion()
                    } else {
                        displayedSuggestion = advanced
                        CompletionManager.shared.currentCompletion = advanced
                        let font = NSFont.systemFont(ofSize: 13, weight: .regular)
                        let attrs = [NSAttributedString.Key.font: font]
                        let shiftPx = (newChar as NSString).size(withAttributes: attrs).width
                        overlayWindowController?.shiftOverlayX(by: shiftPx)
                        overlayWindowController?.updateGhostText(advanced)
                    }
                    lastBufferSnapshot = bufferFallback
                    return .matchedAndAdvanced
                } else {
                    clearDisplayedSuggestion()
                    Task { await PredictionWorker.shared.cancelActiveGeneration() }
                    lastBufferSnapshot = bufferFallback
                    return .invalidated
                }
            } else {
                clearDisplayedSuggestion()
                Task { await PredictionWorker.shared.cancelActiveGeneration() }
                lastBufferSnapshot = bufferFallback
                return .invalidated
            }
        }
        
        lastBufferSnapshot = bufferFallback
        return .noGhostText
    }
    
    private func scheduleGeneration(bufferSnapshot: String, isPunctuation: Bool, bypassDebounce: Bool) {
        debounceTask?.cancel()
        
        // Let CompletionManager do synchronous spelling/snippets first if needed.
        // It's still responsible for auto-correct overriding completions.
        CompletionManager.shared.handleLocalTextChanges(bufferFallback: bufferSnapshot)
        
        if CompletionManager.shared.currentCompletion != nil {
            // A spellcheck or snippet took over the UI
            clearDisplayedSuggestion()
            Task { await PredictionWorker.shared.cancelActiveGeneration() }
            return
        }
        
        generationIDCounter &+= 1
        let genID = generationIDCounter
        
        let delayMilliseconds = bypassDebounce ? 0 : (isPunctuation ? 0 : 150)
        
        debounceTask = Task {
            if delayMilliseconds > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delayMilliseconds) * 1_000_000)
            }
            if Task.isCancelled { return }
            
            // Create snapshot
            let creationTime = CFAbsoluteTimeGetCurrent()
            
            // Need to get text before caret. We can query AccessibilityMonitor.
            // Since we decoupled it, we could have EditorEventBus pass it, but AccessibilityMonitor is a singleton.
            let textBeforeCaret = self.accessibilityMonitor?.getTextBeforeCaret() ?? ""
            let liveBuffer = bufferSnapshot
            
            let snapshot = PredictionSnapshot(
                generationID: genID,
                textBeforeCaret: textBeforeCaret.isEmpty ? liveBuffer : textBeforeCaret,
                liveBuffer: liveBuffer,
                isPunctuation: isPunctuation,
                creationTime: creationTime
            )
            
            await PredictionWorker.shared.submit(snapshot: snapshot)
        }
    }
    
    private func handlePredictionResult(id: UInt64, completion: String, metrics: GenerationMetrics, isFinal: Bool) {
        var finalMetrics = metrics
        finalMetrics.sanitizationStartTime = CFAbsoluteTimeGetCurrent()
        
        // We only care about the latest generation.
        if id != generationIDCounter {
            return
        }
        
        // Retrieve typing since snapshot
        let currentAX = self.accessibilityMonitor?.getTextBeforeCaret() ?? ""
        let currentLine = !currentAX.isEmpty ? currentAX : (self.accessibilityMonitor?.keystrokeBuffer ?? "")

        // A simple prefix comparison: what has been typed since the generation was dispatched?
        // Actually, we can use the liveBuffer diff.
        // Let's use the sanitizer logic from CompletionManager
        var processedCompletion = SuggestionInteractionState.sliceGeneratedSuffix(activeLine: currentLine, rawCompletion: completion)
        processedCompletion = stripMarkdown(processedCompletion)
        
        // We compare what was typed against the generated completion
        let remainder = processedCompletion // Simplified, in reality we might want precise diffing
        
        var finalRemainder = remainder
        if finalRemainder.contains("\n") {
            if let newlineRange = finalRemainder.range(of: "\n") {
                finalRemainder = String(finalRemainder[..<newlineRange.lowerBound])
            }
        }
        
        finalMetrics.sanitizationEndTime = CFAbsoluteTimeGetCurrent()
        
        if !finalRemainder.isEmpty {
            if !isFinal && displayedSuggestion != nil && finalRemainder.count <= displayedSuggestion!.count {
                return // Do not shrink the displayed suggestion for a partial chunk
            }
            self.displayedSuggestion = finalRemainder
            CompletionManager.shared.currentCompletion = finalRemainder
            if let rect = self.accessibilityMonitor?.getCurrentCaretRect() {
                self.overlayWindowController?.moveOverlay(to: rect)
            }
            self.overlayWindowController?.updateText(finalRemainder)
            
            finalMetrics.overlaySwapTime = CFAbsoluteTimeGetCurrent()
            finalMetrics.printReport()
        } else {
            // Empty result
            clearDisplayedSuggestion()
        }
    }
    
    private func stripMarkdown(_ text: String) -> String {
        var result = text
        if result.hasSuffix("```") {
            result = String(result.dropLast(3))
        } else if result.hasSuffix("``") {
            result = String(result.dropLast(2))
        } else if result.hasSuffix("`") {
            result = String(result.dropLast(1))
        }
        return result
    }
}
