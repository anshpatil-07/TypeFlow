import Foundation

actor LLMEngine {
    static let shared = LLMEngine()
    
    private let runtime = TypeFlowLlamaWrapper()
    private var inactivityTimer: Timer?
    
    var isModelReady: Bool { get async { await runtime.isModelReady } }
    
    private func unloadModel() {
        Task { await runtime.unloadModel() }
        print("[TypeFlow-Debug] LLMEngine: Model unloaded due to inactivity")
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
        Task { await loadModelIfNeeded() }
    }

    private func checkMemoryStatus() -> Bool {
        return true // TypeFlowLlamaWrapper uses mmap and strictly bounded n_ctx, zero ARC bloat
    }
    
    func prewarmCache(toneProfile: ToneProfile) async {
        print("[TypeFlow-Debug] LLMEngine: Pre-warming cache for tone \(toneProfile.name)")
        await loadModelIfNeeded()
        resetInactivityTimer()
    }

    func generateCompletion(textBeforeCaret: String, liveBuffer: String, toneProfile: ToneProfile) async -> String {
        print("[TypeFlow-Debug] LLMEngine: generateCompletion called with tone \(toneProfile.name)")
        
        await loadModelIfNeeded()
        resetInactivityTimer()
        
        guard await runtime.isModelReady else {
            print("[TypeFlow-Debug] LLMEngine: Model not ready!")
            return ""
        }
        
        if Task.isCancelled {
            return ""
        }
        
        let suffixResult = PromptBuilder.shared.buildPromptSuffix(textBeforeCaret: textBeforeCaret, liveBuffer: liveBuffer)
        let dynamicPrefixPrompt = PromptBuilder.shared.buildPromptPrefix(systemInstructions: toneProfile.systemInstructions)
        let fullPrompt = dynamicPrefixPrompt + suffixResult.text
        
        do {
            let output = try await runtime.generate(
                prompt: fullPrompt,
                maxTokens: toneProfile.maxTokens,
                temperature: Float(toneProfile.temperature)
            )
            
            var trimmedResult = output.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            
            // ── Swift-level stop-sequence truncation ───────────────────────────────
            // The model is not given native stop tokens via the C-API to avoid
            // breaking C-interop. Instead we truncate at the first newline or control
            // tag opening bracket ('<') here in Swift. Inline ghost-text completions
            // are always single-line; anything after a \n, \r, or control tag is a
            // hallucination and must be discarded immediately.
            let stopChars = CharacterSet.newlines.union(CharacterSet(charactersIn: "<"))
            if let stopRange = trimmedResult.rangeOfCharacter(from: stopChars) {
                let truncated = String(trimmedResult[..<stopRange.lowerBound])
                    .trimmingCharacters(in: .whitespaces)
                print("[TypeFlow-Debug] LLMEngine: Truncated at stop sequence. Kept: '\(truncated)'")
                trimmedResult = truncated
            }
            
            // Clean echo: strip any prefix of the output that overlaps with the tail
            // of the input text (handles the rare case where the model still repeats
            // a word boundary despite the ChatML instruct wrapper).
            let echoedContext = String(textBeforeCaret.suffix(120)).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if !echoedContext.isEmpty {
                let maxOv = min(echoedContext.count, trimmedResult.count)
                for i in stride(from: maxOv, through: 1, by: -1) {
                    let suffix = String(echoedContext.suffix(i))
                    let prefix = String(trimmedResult.prefix(i))
                    if suffix == prefix {
                        trimmedResult = String(trimmedResult.dropFirst(i))
                        break
                    }
                }
            }
            
            if !trimmedResult.isEmpty && textBeforeCaret.hasSuffix(" ") && !trimmedResult.hasPrefix(" ") {
                trimmedResult = " " + trimmedResult
            }
            return trimmedResult
            
        } catch {
            print("[TypeFlow-Debug] LLMEngine: Generation failed: \(error)")
            return ""
        }
    }

    func generateRewrite(selectedText: String, toneProfile: ToneProfile) async -> String {
        print("[TypeFlow-Debug] LLMEngine: generateRewrite called")
        
        await loadModelIfNeeded()
        resetInactivityTimer()
        
        guard await runtime.isModelReady else { return "" }
        if Task.isCancelled { return "" }
        
        let prompt = PromptBuilder.shared.buildRewritePrompt(
            selectedText: selectedText,
            systemInstructions: toneProfile.systemInstructions,
            toneName: toneProfile.name
        )
        
        do {
            let maxTokens = max(100, selectedText.count / 2)
            let output = try await runtime.generate(
                prompt: prompt,
                maxTokens: maxTokens,
                temperature: Float(toneProfile.temperature)
            )
            return output.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        } catch {
            print("[TypeFlow-Debug] LLMEngine: Rewrite failed: \(error)")
            return ""
        }
    }

    func generateSmartReplies(contextText: String) async -> [String] {
        print("[TypeFlow-Debug] LLMEngine: generateSmartReplies called")
        
        await loadModelIfNeeded()
        resetInactivityTimer()
        
        guard await runtime.isModelReady else { return [] }
        if Task.isCancelled { return [] }
        
        let prompt = """
        You are a context-aware smart reply assistant. Based on the conversation context provided below, generate exactly 3 short, distinct reply options (e.g. Professional, Casual, Concise) that the user could send in response.
        Output the 3 options separated EXACTLY by the delimiter '|||' and nothing else. No formatting, no prefixes.
        
        Context:
        \(contextText)
        
        Replies:
        """
        
        do {
            let output = try await runtime.generate(
                prompt: prompt,
                maxTokens: 150,
                temperature: 0.6
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

    private func loadModelIfNeeded() async {
        if await runtime.isModelReady { return }
        
        do {
            let modelId = SettingsManager.shared.activeModelId
            print("[TypeFlow-Debug] LLMEngine: Loading model: \(modelId)")
            
            let ggufPath = "\(NSHomeDirectory())/Documents/gemma-4-E2B.Q4_K_M.gguf"
            
            try await runtime.loadModel(path: ggufPath)
            print("[TypeFlow-Debug] LLMEngine: Model loaded successfully.")
        } catch {
            print("[TypeFlow-Debug] LLMEngine: Failed to load model: \(error)")
        }
    }
}
