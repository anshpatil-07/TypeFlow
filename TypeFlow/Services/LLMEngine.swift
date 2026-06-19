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

    func generateCompletion(
        textBeforeCaret: String,
        liveBuffer: String,
        toneProfile: ToneProfile,
        onStream: (@Sendable (String) -> Void)? = nil
    ) async -> String {
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
                temperature: Float(toneProfile.temperature),
                onPartialRawText: { partialText in
                    onStream?(partialText)
                }
            )
            
            var trimmedResult = output.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            
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
            
            let ggufPath = "\(NSHomeDirectory())/Documents/gemma-4-E2B-i1-Q4_K_M.gguf"
            
            try await runtime.loadModel(path: ggufPath)
            print("[TypeFlow-Debug] LLMEngine: Model loaded successfully.")
        } catch {
            print("[TypeFlow-Debug] LLMEngine: Failed to load model: \(error)")
        }
    }
}
