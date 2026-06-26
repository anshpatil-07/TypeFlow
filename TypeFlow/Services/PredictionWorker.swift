import Foundation

final class FirstTokenTracker: @unchecked Sendable {
    private let lock = NSLock()
    var logged = false
    var time: CFAbsoluteTime = 0
    func markIfFirst() -> CFAbsoluteTime? {
        lock.lock()
        defer { lock.unlock() }
        if !logged {
            logged = true
            time = CFAbsoluteTimeGetCurrent()
            return time
        }
        return nil
    }
}


actor PredictionWorker {
    static let shared = PredictionWorker()
    
    private var activeGenerationID: UInt64?
    private var activeTask: Task<Void, Never>?
    private var queuedSnapshot: PredictionSnapshot?
    
    typealias ResultCallback = @Sendable (UInt64, String, GenerationMetrics, Bool) -> Void
    private var onResultReady: ResultCallback?
    
    private init() {}
    
    func setCallback(_ callback: @escaping ResultCallback) {
        self.onResultReady = callback
    }
    
    func submit(snapshot: PredictionSnapshot) {
        if activeTask != nil {
            queuedSnapshot = snapshot
        } else {
            startGeneration(for: snapshot)
        }
    }
    
    func cancelActiveGeneration() {
        activeTask?.cancel()
        activeTask = nil
        activeGenerationID = nil
        
        if let next = queuedSnapshot {
            queuedSnapshot = nil
            startGeneration(for: next)
        }
    }
    
    private func startGeneration(for snapshot: PredictionSnapshot) {
        var metrics = GenerationMetrics(generationID: snapshot.generationID, snapshotCreationTime: snapshot.creationTime)
        
        let task = Task {
            metrics.promptBuildStartTime = CFAbsoluteTimeGetCurrent()
            
            // Build prompt
            let hardcodedInstructions = "Complete the text. Output only the next few words. No explanation."
            let temperature = Float(UserDefaults.standard.double(forKey: "globalTemperature"))
            var maxTokens = UserDefaults.standard.integer(forKey: "globalMaxLength")
            if maxTokens == 0 { maxTokens = 20 }
            
            // We use main thread for prompt building to access Settings/Context managers safely if needed,
            // but actually PromptBuilder does it synchronously.
            let suffixResult = PromptBuilder.shared.buildPromptSuffix(textBeforeCaret: snapshot.textBeforeCaret, liveBuffer: snapshot.liveBuffer)
            let dynamicPrefixPrompt = PromptBuilder.shared.buildPromptPrefix(systemInstructions: hardcodedInstructions)
            let fullPrompt = dynamicPrefixPrompt + suffixResult.text
            
            metrics.promptBuildEndTime = CFAbsoluteTimeGetCurrent()
            
            if Task.isCancelled {
                self.onTaskCompleted()
                return
            }
            
            metrics.inferenceStartTime = CFAbsoluteTimeGetCurrent()
            
            // Track first token
            let tracker = FirstTokenTracker()
            
            // Run inference
            let genID = snapshot.generationID
            let callback = self.onResultReady
            let metricsRef = metrics // Note: metrics is a reference type, but accessing it from Sendable closure might be risky. Wait, metrics is NOT sent to partial callbacks to avoid race conditions. We'll just send an empty metrics object for partials!
            
            let completion = await LLMEngine.shared.generateRaw(
                prompt: fullPrompt,
                maxTokens: maxTokens,
                temperature: temperature,
                onStream: { partialText in
                    _ = tracker.markIfFirst()
                    
                    // Confidence Gate for Partial Completions
                    let minLength = 10
                    let wordBoundaryChars: Set<Character> = [" ", "\n", ".", ",", ";", ":", "!", "?", ")", "]"]
                    
                    if partialText.count >= minLength {
                        if let lastChar = partialText.last, wordBoundaryChars.contains(lastChar) {
                            // Publish atomic partial chunk
                            let partialMetrics = GenerationMetrics(generationID: genID)
                            callback?(genID, partialText, partialMetrics, false)
                        }
                    }
                }
            )
            metrics.firstTokenTime = tracker.time > 0 ? tracker.time : CFAbsoluteTimeGetCurrent()
            
            metrics.inferenceEndTime = CFAbsoluteTimeGetCurrent()
            
            if Task.isCancelled {
                self.onTaskCompleted()
                return
            }
            
            // Send back to coordinator
            self.onResultReady?(snapshot.generationID, completion, metrics, true)
            self.onTaskCompleted()
        }
        
        activeTask = task
        activeGenerationID = snapshot.generationID
    }
    
    private func onTaskCompleted() {
        activeTask = nil
        activeGenerationID = nil
        
        if let next = queuedSnapshot {
            queuedSnapshot = nil
            startGeneration(for: next)
        }
    }
}
