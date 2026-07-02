import Foundation

enum ModelFamily: String {
    case gemmaCausal = "gemmaCausal"
    case qwenCoderFIM = "qwenCoderFIM"
    case unknown = "unknown"
}

enum PromptMode {
    case causal
    case fim
}

struct ModelProfile {
    let path: String
    let family: ModelFamily
    let promptMode: PromptMode
    
    let fimPrefix: String?
    let fimSuffix: String?
    let fimMiddle: String?
    
    let stopTokens: [String]
    let maxTokens: Int
    let temperature: Float
}

extension ModelProfile {
    static let gemmaDefault = ModelProfile(
        path: "",
        family: .gemmaCausal,
        promptMode: .causal,
        fimPrefix: nil,
        fimSuffix: nil,
        fimMiddle: nil,
        stopTokens: ["<|im_end|>", "<|endoftext|>"],
        maxTokens: 30,
        temperature: 0.1
    )
    
    static let qwenFIM = ModelProfile(
        path: "",
        family: .qwenCoderFIM,
        promptMode: .fim,
        fimPrefix: "<|fim_prefix|>",
        fimSuffix: "<|fim_suffix|>",
        fimMiddle: "<|fim_middle|>",
        stopTokens: ["<|file_separator|>", "<|endoftext|>", "<|im_end|>"],
        maxTokens: 30,
        temperature: 0.1
    )
    
    static func current() -> ModelProfile {
        let modelPath = UserDefaults.standard.string(forKey: "modelPath") ?? ""
        let profileID = UserDefaults.standard.string(forKey: "modelProfileID") ?? "unknown"
        
        if profileID == "qwenCoderFIM" {
            return ModelProfile(
                path: modelPath,
                family: .qwenCoderFIM,
                promptMode: .fim,
                fimPrefix: qwenFIM.fimPrefix,
                fimSuffix: qwenFIM.fimSuffix,
                fimMiddle: qwenFIM.fimMiddle,
                stopTokens: qwenFIM.stopTokens,
                maxTokens: qwenFIM.maxTokens,
                temperature: qwenFIM.temperature
            )
        } else if profileID == "gemmaCausal" {
            return ModelProfile(
                path: modelPath,
                family: .gemmaCausal,
                promptMode: .causal,
                fimPrefix: nil,
                fimSuffix: nil,
                fimMiddle: nil,
                stopTokens: gemmaDefault.stopTokens,
                maxTokens: gemmaDefault.maxTokens,
                temperature: gemmaDefault.temperature
            )
        }
        
        // Default to gemma fallback if unspecified, but fail closed on path
        return ModelProfile(
            path: modelPath,
            family: .unknown,
            promptMode: .causal,
            fimPrefix: nil,
            fimSuffix: nil,
            fimMiddle: nil,
            stopTokens: gemmaDefault.stopTokens,
            maxTokens: gemmaDefault.maxTokens,
            temperature: gemmaDefault.temperature
        )
    }
}


actor LLMEngine {
    static let shared = LLMEngine()
    
    private let runtime = TypeFlowLlamaWrapper()
    private var inactivityTimer: Timer?
    private var modelLoadTask: Task<Void, Never>?
    private var latestModelLoadRequestID: UInt64?
    
    private(set) var activeProfile: ModelProfile = ModelProfile.current()
    
    var isModelReady: Bool { get async { await runtime.isModelReady } }
    
    private func unloadModel() {
        Task { await runtime.unloadModel() }
        print("[TypeFlow-Debug] LLMEngine: Model unloaded due to inactivity")
    }

    private func contextAuditPreview(_ text: String, limit: Int = 220) -> String {
        let escaped = text
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
        if escaped.count <= limit { return escaped }
        return "..." + String(escaped.suffix(limit))
    }

    private func logContextAudit(_ message: String) {
        print("[TypeFlow-ContextAudit] \(message)")
    }
    
    private func resetInactivityTimer() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            Task {
                await self.invalidateTimer()
            }
            let timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                Task {
                    await self.unloadModel()
                }
            }
            Task {
                await self.setTimer(timer)
            }
        }
    }
    
    private func invalidateTimer() {
        inactivityTimer?.invalidate()
        inactivityTimer = nil
    }
    
    private func setTimer(_ timer: Timer) {
        inactivityTimer = timer
    }
    
    func invalidateKVCache() {
        print("[TypeFlow-Debug] LLMEngine: KV cache invalidated (handled via wrapper clear per sequence)")
    }

    private init() {
        Task { await loadModelIfNeeded(requestID: nil) }
    }

    private func checkMemoryStatus() -> Bool {
        return true // TypeFlowLlamaWrapper uses mmap and strictly bounded n_ctx, zero ARC bloat
    }
    
    func prewarmCache() async {
        print("[TypeFlow-Debug] LLMEngine: Pre-warming cache")
        await loadModelIfNeeded(requestID: nil)
        resetInactivityTimer()
    }

    func generateCompletion(
        textBeforeCaret: String,
        liveBuffer: String,
        cancellationToken: LlamaGenerationCancellationToken? = nil,
        policy: AutocompleteContextPolicy = .fullContext,
        onStream: (@Sendable (String) -> Void)? = nil
    ) async -> String {
        print("[TypeFlow-Debug] LLMEngine: generateCompletion called")

        let instrumentationRequestID = cancellationToken?.requestID
        let instrumentationWorkID = cancellationToken?.workID
        let wasReadyBeforeLoad = await runtime.isModelReady
        if let requestID = instrumentationRequestID, !wasReadyBeforeLoad {
            print("[ModelReadiness] generation allowed to enter load path requestID=\(requestID) isReady=false")
        }

        await loadModelIfNeeded(requestID: instrumentationRequestID)
        resetInactivityTimer()

        if Task.isCancelled || cancellationToken?.isCancelled == true {
            if let requestID = instrumentationRequestID {
                print("[ModelReadiness] dropped stale queued requestID=\(requestID)")
            }
            return ""
        }

        guard await runtime.isModelReady else {
            print("[TypeFlow-Debug] LLMEngine: Model not ready!")
            return ""
        }

        if let requestID = instrumentationRequestID {
            print("[ModelReadiness] generation proceeding requestID=\(requestID) isReady=true")
        }

        if Task.isCancelled {
            return ""
        }
        
        let hardcodedInstructions = "Complete the text. Output only the next few words. No explanation."
        let temperature = Float(UserDefaults.standard.double(forKey: "globalTemperature"))
        var maxTokens = UserDefaults.standard.integer(forKey: "globalMaxLength")
        if maxTokens == 0 { maxTokens = 20 }
        
        LatencyInstrumentation.shared.promptBuildStart(requestID: instrumentationRequestID, workID: instrumentationWorkID)
        let fullPrompt = PromptBuilder.shared.buildPrompt(textBeforeCaret: textBeforeCaret, liveBuffer: liveBuffer, systemInstructions: hardcodedInstructions, requestID: instrumentationRequestID, workID: instrumentationWorkID)
        // Extract suffixResult just for context audit log compatibility
        let suffixResult = PromptBuilder.shared.buildPromptSuffix(textBeforeCaret: textBeforeCaret, liveBuffer: liveBuffer)
        LatencyInstrumentation.shared.promptBuildEnd(requestID: instrumentationRequestID, workID: instrumentationWorkID)
        logContextAudit("LLMEngine generate textBeforeCaretLen=\(textBeforeCaret.count) textBeforeCaret='\(contextAuditPreview(textBeforeCaret))' liveBufferLen=\(liveBuffer.count) liveBuffer='\(contextAuditPreview(liveBuffer))' suffixLen=\(suffixResult.text.count) suffix='\(contextAuditPreview(suffixResult.text))' fullPromptLen=\(fullPrompt.count) fullPromptTail='\(contextAuditPreview(fullPrompt))'")
        
        do {
            LatencyInstrumentation.shared.llamaGenerationStart(requestID: instrumentationRequestID, workID: instrumentationWorkID)
            let output = try await runtime.generate(
                prompt: fullPrompt,
                maxTokens: activeProfile.maxTokens,
                temperature: activeProfile.temperature == 0.0 ? 0.2 : activeProfile.temperature,
                cancellationToken: cancellationToken,
                workID: instrumentationWorkID,
                onPartialRawText: { partialText in
                    LatencyInstrumentation.shared.firstToken(requestID: instrumentationRequestID, workID: instrumentationWorkID)
                    if cancellationToken?.isCancelled == true {
                        if let requestID = cancellationToken?.requestID,
                           cancellationToken?.shouldLogStreamSuppression() == true {
                            print("[Stage1B] stale/cancelled stream token suppressed requestID=\(requestID)")
                        }
                        return
                    }
                    onStream?(partialText)
                }
            )
            
            var trimmedResult = output.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            
            if !trimmedResult.isEmpty && textBeforeCaret.hasSuffix(" ") && !trimmedResult.hasPrefix(" ") {
                trimmedResult = " " + trimmedResult
            }
            return trimmedResult
            
        } catch is CancellationError {
            if let requestID = cancellationToken?.requestID,
               cancellationToken?.shouldLogCancellationExit() == true {
                print("[Stage1B] generation exited cancelled requestID=\(requestID)")
            }
            return ""
        } catch {
            print("[TypeFlow-Debug] LLMEngine: Generation failed: \(error)")
            return ""
        }
    }

    func generateRewrite(selectedText: String) async -> String {
        print("[TypeFlow-Debug] LLMEngine: generateRewrite called")
        
        await loadModelIfNeeded(requestID: nil)
        resetInactivityTimer()
        
        guard await runtime.isModelReady else { return "" }
        if Task.isCancelled { return "" }
        
        let hardcodedInstructions = "Rewrite the text professionally."
        let temperature = Float(UserDefaults.standard.double(forKey: "globalTemperature"))
        
        let prompt = PromptBuilder.shared.buildRewritePrompt(
            selectedText: selectedText,
            systemInstructions: hardcodedInstructions,
            toneName: "Professional"
        )
        
        do {
            let maxTokens = max(100, selectedText.count / 2)
            let output = try await runtime.generate(
                prompt: prompt,
                maxTokens: activeProfile.maxTokens,
                temperature: activeProfile.temperature == 0.0 ? 0.2 : activeProfile.temperature
            )
            return output.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        } catch {
            print("[TypeFlow-Debug] LLMEngine: Rewrite failed: \(error)")
            return ""
        }
    }

    func generateSmartReplies(contextText: String) async -> [String] {
        print("[TypeFlow-Debug] LLMEngine: generateSmartReplies called")
        
        await loadModelIfNeeded(requestID: nil)
        resetInactivityTimer()
        
        guard await runtime.isModelReady else { return [] }
        if Task.isCancelled { return [] }
        
        // Smart reply uses a base model conditioning format.
        // The model continues from the "Reply options:" label naturally.
        let prompt = """
        Context of the conversation:
        \(contextText)

        Generate exactly 3 short reply options (Professional, Casual, Concise).
        Output the 3 options separated EXACTLY by the delimiter '|||' and nothing else.

        Reply options: 
        """
        
        do {
            let output = try await runtime.generate(
                prompt: prompt,
                maxTokens: activeProfile.maxTokens,
                temperature: activeProfile.temperature
            )
            
            let options = output.components(separatedBy: "|||")
                .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            
            return Array(options.prefix(3))
        } catch {
            print("[TypeFlow-Debug] LLMEngine: SmartReply failed: \(error)")
            return []
        }
    }

    private func loadModelIfNeeded(requestID: UInt64?) async {
        if await runtime.isModelReady { return }

        if let existingLoad = modelLoadTask {
            if let requestID {
                if let oldRequestID = latestModelLoadRequestID, oldRequestID != requestID {
                    print("[ModelReadiness] coalesced queued autocomplete request oldRequestID=\(oldRequestID) newRequestID=\(requestID)")
                } else if latestModelLoadRequestID == nil {
                    print("[ModelReadiness] model load started requestID=\(requestID)")
                }
                latestModelLoadRequestID = requestID
            }
            await existingLoad.value
            return
        }

        latestModelLoadRequestID = requestID
        if let requestID {
            print("[ModelReadiness] model load started requestID=\(requestID)")
        }

        let loadTask = Task { [runtime] in
            do {
                if await runtime.isModelReady { return }
                
                activeProfile = ModelProfile.current()
                
                if activeProfile.path.isEmpty {
                    print("[TypeFlow-Error] LLMEngine: No model path configured. Failing closed.")
                    throw NSError(domain: "LLMEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Model path not configured."])
                }
                
                print("==========================================")
                print("[TypeFlow-Startup] MODEL CONFIGURATION")
                print("- Model Path: \(activeProfile.path)")
                print("- Model Profile: \(activeProfile.family.rawValue)")
                print("- FIM Enabled: \(activeProfile.promptMode == .fim)")
                if activeProfile.promptMode == .fim {
                    print("- FIM Tokens: Prefix=\(activeProfile.fimPrefix ?? ""), Suffix=\(activeProfile.fimSuffix ?? ""), Middle=\(activeProfile.fimMiddle ?? "")")
                }
                let minDebounce = 25
                let maxDebounce = 75
                print("- Debounce: \(minDebounce)ms - \(maxDebounce)ms")
                print("- Sampler Settings: temp=\(activeProfile.temperature), maxTokens=\(activeProfile.maxTokens)")
                print("- Stop Tokens: \(activeProfile.stopTokens)")
                print("==========================================")
                
                try await runtime.loadModel(profile: activeProfile)
                print("[TypeFlow-Debug] LLMEngine: Model loaded successfully.")
            } catch {
                print("[TypeFlow-Debug] LLMEngine: Failed to load model: \(error)")
            }
        }

        modelLoadTask = loadTask
        await loadTask.value
        modelLoadTask = nil

        if await runtime.isModelReady, let latestRequestID = latestModelLoadRequestID {
            print("[ModelReadiness] model ready; continuing latest requestID=\(latestRequestID)")
        }
        latestModelLoadRequestID = nil
    }
}
