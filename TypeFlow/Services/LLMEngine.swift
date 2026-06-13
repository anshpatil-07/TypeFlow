import Foundation
@preconcurrency import MLXLLM
@preconcurrency import MLXLMCommon
@preconcurrency import MLXHuggingFace
@preconcurrency import Hub
@preconcurrency import Tokenizers
@preconcurrency import HuggingFace
import MLX
import Darwin

// ─────────────────────────────────────────────────────────────────────────────
// LLMEngine — Real on-device inference via MLXLLM (Hard-Lock Thread-Safe)
//
// CONCURRENCY CONTRACT:
//   mlxLock is an NSLock that serializes ALL calls into the MLX C++ runtime.
//   Swift actor isolation alone is insufficient because container.perform { }
//   dispatches its closure to a global concurrent thread pool, escaping actor
//   isolation. The lock is the ONLY barrier that guarantees single-threaded
//   access to mlx::core::detail::compile and the internal unordered_map.
//
//   Rule: any code that touches modelContext.model(...), eval(...), or
//         MLXLMCommon.generate(...) MUST be wrapped in mlxLock.withLock { }.
//         If the task is cancelled while waiting for the lock, drop it.
// ─────────────────────────────────────────────────────────────────────────────

struct KVCacheError: Error {
    let message: String
}


struct GenerationResult: Sendable {
    let outputText: String
}


private final class CacheStore: @unchecked Sendable {
    var cache: [KVCache]?
    var prefixString: String = ""
}

actor LLMEngine {
    static let shared = LLMEngine()
    
    private let cacheStore = CacheStore()

    // Lazily-loaded model container — loaded once, reused on every completion.
    private var modelContainer: ModelContainer?
    private var isLoading = false
    private var loadError: Error?
    private var currentLoadedModelId: String?
    private var inactivityTimer: Timer?
    
    var isModelReady: Bool { modelContainer != nil }
    
    private func unloadModel() {
        self.modelContainer = nil
        self.invalidateKVCache()
        print("[TypeFlow-Debug] LLMEngine: Model unloaded due to 5 minutes of inactivity")
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
    
    /// Explicitly invalidate the KV cache — call only when tone or personalization changes.
    func invalidateKVCache() {
        cacheStore.cache = nil
        cacheStore.prefixString = ""
        print("[TypeFlow-Debug] LLMEngine: KV cache explicitly invalidated")
    }

    private init() {
        // Limit MLX cache size to 128 MB to avoid growing RAM usage unbounded
        MLX.Memory.cacheLimit = 128 * 1024 * 1024
        
        // Kick off model load in the background so the first keystroke
        // doesn't block waiting for weights.
        Task { await loadModelIfNeeded() }
    }

    /// Check if the system has at least 2GB of available memory.
    private func checkMemoryStatus() -> Bool {
        let hostPort = mach_host_self()
        var pageSize: vm_size_t = 0
        guard host_page_size(hostPort, &pageSize) == KERN_SUCCESS else { return true }
        
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        
        let statsResult = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
            }
        }
        
        guard statsResult == KERN_SUCCESS else { return true }
        
        // Available memory is free pages + inactive pages + speculative pages
        let availablePages = UInt64(vmStats.free_count) + UInt64(vmStats.inactive_count) + UInt64(vmStats.speculative_count)
        let availableBytes = availablePages * UInt64(pageSize)
        
        let twoGB: UInt64 = 2 * 1024 * 1024 * 1024
        return availableBytes >= twoGB
    }
    
    /// Pre-warm the cache when the active app changes so zero-latency can be achieved.
    func prewarmCache(toneProfile: ToneProfile) async {
        print("[TypeFlow-Debug] LLMEngine: Pre-warming cache for tone \(toneProfile.name)")
        PromptBuilder.shared.invalidateFrozenPrefix()
        
        await loadModelIfNeeded()
        resetInactivityTimer()
        
        guard let container = modelContainer else { return }
        guard checkMemoryStatus() else { return }
        
        let staticPrefixPrompt = PromptBuilder.shared.buildStaticPrefix(systemInstructions: toneProfile.systemInstructions)
        let cacheStore = self.cacheStore
        await container.perform { modelContext in
            defer { 
                // Barrier to ensure asyncEval background tasks finish before unlocking
                MLX.eval(MLXArray(0))
                MLX.Memory.clearCache()
            }
            
            if cacheStore.cache == nil || cacheStore.prefixString != staticPrefixPrompt {
                print("[TypeFlow-Debug] LLMEngine: Pre-warm cache miss — rebuilding base KV prefix...")
                
                let prefixTokens = modelContext.tokenizer.encode(text: staticPrefixPrompt)
                let newCache = modelContext.model.newCache(parameters: nil)
                if !prefixTokens.isEmpty {
                    let prefixMLXTokens = MLXArray(prefixTokens)
                    _ = modelContext.model(prefixMLXTokens[.newAxis], cache: newCache)
                    eval(newCache)
                }
                print("[TypeFlow-Debug] LLMEngine: Pre-warm complete with \(prefixTokens.count) tokens.")
                cacheStore.cache = newCache
                cacheStore.prefixString = staticPrefixPrompt
            } else {
                print("[TypeFlow-Debug] LLMEngine: Pre-warm cache hit — reusing base KV prefix.")
            }
        }
    }

    /// Generate a completion for the given text-before-caret.
    func generateCompletion(textBeforeCaret: String, liveBuffer: String, toneProfile: ToneProfile) async -> String {
        print("[TypeFlow-Debug] LLMEngine: generateCompletion called with tone \(toneProfile.name) (temp: \(toneProfile.temperature), maxTokens: \(toneProfile.maxTokens))")
        
        await loadModelIfNeeded()
        resetInactivityTimer()
        
        guard let container = modelContainer else {
            print("[TypeFlow-Debug] LLMEngine: modelContainer is nil! Returning empty string.")
            if let error = loadError {
                print("[TypeFlow-Debug] LLMEngine: Previous load error: \(error)")
            }
            return ""
        }
        
        guard checkMemoryStatus() else {
            print("[TypeFlow-Debug] LLMEngine: Low memory guard triggered! Cancelling generation.")
            return ""
        }
        
        if textBeforeCaret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            PromptBuilder.shared.invalidateFrozenPrefix()
        }

        let dynamicPrefixPrompt = PromptBuilder.shared.buildPromptPrefix(systemInstructions: toneProfile.systemInstructions)
        let cacheStore = self.cacheStore
        
        // Check for task cancellation before entering the lock
        if Task.isCancelled {
            print("[TypeFlow-Debug] LLMEngine: Task cancelled before acquiring lock, dropping.")
            return ""
        }
        
        let result: GenerationResult = await container.perform { modelContext -> GenerationResult in
            // HARD SERIAL LOCK: blocks this thread until MLX is free.
            // If the calling task was cancelled while blocked here, drop immediately after acquiring.
            defer { 
                // Barrier to ensure asyncEval background tasks finish before unlocking
                MLX.eval(MLXArray(0))
                MLX.Memory.clearCache()
            }
            
            // Re-check cancellation immediately after acquiring the lock.
            if Task.isCancelled {
                print("[TypeFlow-Debug] LLMEngine: Task cancelled after acquiring lock, dropping.")
                return GenerationResult(outputText: "")
            }
            
            do {
                let suffixResult = PromptBuilder.shared.buildPromptSuffix(textBeforeCaret: textBeforeCaret, liveBuffer: liveBuffer)
                let suffixPrompt = suffixResult.text
                
                if suffixResult.requiresHealing {
                    cacheStore.cache = nil
                    print("[TypeFlow-Debug] LLMEngine: Bypassing base cache due to token healing boundary.")
                }
                
                if cacheStore.cache == nil || cacheStore.prefixString != dynamicPrefixPrompt {
                    print("[TypeFlow-Debug] LLMEngine: Base cache miss — rebuilding KV prefix...")
                    
                    let prefixTokens = modelContext.tokenizer.encode(text: dynamicPrefixPrompt)
                    let newCache = modelContext.model.newCache(parameters: nil)
                    
                    if !prefixTokens.isEmpty {
                        let prefixMLXTokens = MLXArray(prefixTokens)
                        _ = modelContext.model(prefixMLXTokens[.newAxis], cache: newCache)
                        eval(newCache)
                    }
                    cacheStore.cache = newCache
                    cacheStore.prefixString = dynamicPrefixPrompt
                    print("[TypeFlow-Debug] LLMEngine: Base cache rebuilt with \(prefixTokens.count) tokens.")
                } else {
                    print("[TypeFlow-Debug] LLMEngine: Base cache hit — cloning prefix.")
                }
                
                guard let baseCache = cacheStore.cache else {
                    throw KVCacheError(message: "Failed to resolve base KV cache")
                }
                
                var suffixTokens = modelContext.tokenizer.encode(text: suffixPrompt)
                
                // CRITICAL FIX: The MLX Tokenizer may automatically prepend a BOS token to every encode call.
                // Since the prefix already has a BOS token, appending a second BOS token in the middle
                // of the generation sequence destroys the causal mask and causes severe hallucinations (e.g., /w_pass).
                let bosTokens = modelContext.tokenizer.encode(text: "")
                if let bosTokenId = bosTokens.first, let firstSuffixId = suffixTokens.first, bosTokenId == firstSuffixId {
                    suffixTokens.removeFirst()
                    print("[TypeFlow-Debug] LLMEngine: Stripped illegal double BOS token from suffix.")
                }
                
                guard !suffixTokens.isEmpty else {
                    print("[TypeFlow-Debug] LLMEngine: No suffix tokens to generate, returning empty string.")
                    return GenerationResult(outputText: "")
                }
                
                let generatorCache = baseCache.map { $0.copy() }
                let suffixInput = LMInput(tokens: MLXArray(suffixTokens))
                
                print("[TypeFlow-Debug] LLMEngine: Starting generate stream with \(suffixTokens.count) suffix tokens...\n--- FULL COMBINED PROMPT LOG ---\n\(dynamicPrefixPrompt)\(suffixPrompt)\n--------------------------------")
                let isClipboard = PromptBuilder.shared.hasClipboardTrigger(textBeforeCaret: textBeforeCaret)
                let activeMaxTokens = isClipboard ? 150 : toneProfile.maxTokens
                let params = GenerateParameters(maxTokens: activeMaxTokens, temperature: Float(toneProfile.temperature), repetitionPenalty: 1.15)
                
                var iterator = try TokenIterator(
                    input: suffixInput, model: modelContext.model, cache: generatorCache, parameters: params)
                var detokenizer = NaiveStreamingDetokenizer(tokenizer: modelContext.tokenizer)
                
                var outputText = ""
                let stopTokens = [
                    "<end_of_turn>",
                    "</end_of_turn>",
                    "<start_of_turn>",
                    "</start_of_turn>",
                    "<eos>",
                    "</s>",
                    "</completion>",
                    "<turn|>",
                    "<|channel>",
                    "thought",
                    "User:",
                    "\n"
                ]

                while let token = iterator.next() {
                    if Task.isCancelled {
                        print("[TypeFlow-Debug] LLMEngine: Generation task was cancelled mid-stream. Aborting.")
                        break
                    }
                    
                    detokenizer.append(token: token)
                    if let text = detokenizer.next() {
                        outputText += text
                        print("[TypeFlow-Debug] LLMEngine Chunk: '\(text)'")

                        var shouldStop = false
                        for stopToken in stopTokens {
                            if let range = outputText.range(of: stopToken) {
                                outputText = String(outputText[..<range.lowerBound])
                                print("[TypeFlow-Debug] LLMEngine: Found stop token '\(stopToken)', halting stream.")
                                shouldStop = true
                                break
                            }
                        }
                        if shouldStop { break }
                    }
                }
                

                print("[TypeFlow-Debug] LLMEngine: Stream finished. Total output: '\(outputText)'")
                return GenerationResult(outputText: outputText)
            } catch {
                print("[TypeFlow-Debug] LLMEngine Error during MLX inference: \(error)")
                return GenerationResult(outputText: "")
            }
        }
        
        MLX.Memory.clearCache()
        
        var cleanResult = result.outputText
        if let range = cleanResult.range(of: "</completion>") {
            cleanResult = String(cleanResult[..<range.lowerBound])
        }
        
        var trimmedResult = cleanResult.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        
        // Strict case-sensitive overlap strip: find the longest suffix of echoedContext
        // that exactly matches a prefix of trimmedResult, then drop it.
        let echoedContext = String(textBeforeCaret.suffix(120)).trimmingCharacters(in: .whitespacesAndNewlines)
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
        
        print("[TypeFlow-Debug] LLMEngine: Generation successful. Result: '\(trimmedResult)'")
        return trimmedResult
    }

    // ── Model loading (MLXLLM) ────────────────────────────────────────────────
    
    private func loadModelIfNeeded() async {
        let activeModelId = SettingsManager.shared.activeModelId
        
        // If the active model changed, invalidate the current one
        if currentLoadedModelId != activeModelId {
            modelContainer = nil
            currentLoadedModelId = nil
            loadError = nil
            MLX.eval(MLXArray(0))
            MLX.Memory.clearCache()
        }
        
        guard modelContainer == nil, !isLoading else { return }
        isLoading = true
        NotificationCenter.default.post(name: Notification.Name("TypeFlowModelLoadingStateChanged"), object: true)

        do {
            let config = ModelConfiguration(
                id: activeModelId,
                extraEOSTokens: ["<end_of_turn>"]
            )
            self.modelContainer = try await #huggingFaceLoadModelContainer(configuration: config)
            self.currentLoadedModelId = activeModelId
            print("[TypeFlow] Model loaded: \(config.id)")
        } catch {
            self.loadError = error
            print("[TypeFlow] Model load failed: \(error)")
        }

        isLoading = false
        NotificationCenter.default.post(name: Notification.Name("TypeFlowModelLoadingStateChanged"), object: false)
    }
    
    func generateRewrite(selectedText: String, toneProfile: ToneProfile) async -> String {
        await loadModelIfNeeded()
        resetInactivityTimer()
        guard let container = modelContainer else {
            print("[TypeFlow-Debug] LLMEngine: modelContainer is nil for rewrite")
            return ""
        }
        guard checkMemoryStatus() else {
            print("[TypeFlow-Debug] LLMEngine: Low memory guard triggered for rewrite")
            return ""
        }
        
        if Task.isCancelled { return "" }
        
        let result: String = await container.perform { (modelContext: ModelContext) async -> String in
            defer { 
                // Barrier to ensure asyncEval background tasks finish before unlocking
                MLX.eval(MLXArray(0))
                MLX.Memory.clearCache()
            }
            
            if Task.isCancelled { return "" }
            
            do {
                let prompt = PromptBuilder.shared.buildRewritePrompt(
                    selectedText: selectedText,
                    systemInstructions: toneProfile.systemInstructions,
                    toneName: toneProfile.name
                )
                let input = UserInput(prompt: prompt)
                let prepared = try await modelContext.processor.prepare(input: input)
                
                let maxTokens = max(100, selectedText.count / 2)
                let params = GenerateParameters(maxTokens: maxTokens, temperature: Float(toneProfile.temperature))
                
                var iterator = try TokenIterator(
                    input: prepared, model: modelContext.model, cache: modelContext.model.newCache(parameters: nil), parameters: params)
                var detokenizer = NaiveStreamingDetokenizer(tokenizer: modelContext.tokenizer)
                
                var outputText = ""
                let stopTokens = [
                    "<end_of_turn>",
                    "</end_of_turn>",
                    "<start_of_turn>",
                    "</start_of_turn>",
                    "<eos>",
                    "</s>",
                    "</completion>",
                    "<turn|>",
                    "<|channel>",
                    "thought"
                ]
                
                while let token = iterator.next() {
                    if Task.isCancelled { break }
                    detokenizer.append(token: token)
                    if let text = detokenizer.next() {
                        outputText += text
                        
                        var shouldStop = false
                        for stopToken in stopTokens {
                            if let range = outputText.range(of: stopToken) {
                                outputText = String(outputText[..<range.lowerBound])
                                shouldStop = true
                                break
                            }
                        }
                        if shouldStop { break }
                    }
                }
                

                return outputText
            } catch {
                print("[TypeFlow-Debug] LLMEngine rewrite error: \(error)")
                return ""
            }
        }
        
        // MLX.Memory.clearCache() moved inside lock
        
        var cleanResult = result
        if let range = cleanResult.range(of: "</completion>") {
            cleanResult = String(cleanResult[..<range.lowerBound])
        }
        return cleanResult.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }
    
    func generateSmartReplies(contextText: String) async -> [String] {
        await loadModelIfNeeded()
        resetInactivityTimer()
        guard let container = modelContainer else {
            print("[TypeFlow-Debug] LLMEngine: modelContainer is nil for smart replies")
            return []
        }
        guard checkMemoryStatus() else {
            print("[TypeFlow-Debug] LLMEngine: Low memory guard triggered for smart replies")
            return []
        }
        
        if Task.isCancelled { return [] }
        
        let result: String = await container.perform { (modelContext: ModelContext) async -> String in
            defer { 
                // Barrier to ensure asyncEval background tasks finish before unlocking
                MLX.eval(MLXArray(0))
                MLX.Memory.clearCache()
            }
            
            if Task.isCancelled { return "" }
            
            do {
                let prompt = """
                You are a context-aware smart reply assistant. Based on the conversation context provided below, generate exactly 3 short, distinct reply options (e.g. Professional, Casual, Concise) that the user could send in response.
                Output the 3 options separated EXACTLY by the delimiter '|||' and nothing else. No formatting, no prefixes.
                
                Context:
                \(contextText)
                
                Replies:
                """
                let input = UserInput(prompt: prompt)
                let prepared = try await modelContext.processor.prepare(input: input)
                
                let params = GenerateParameters(maxTokens: 150, temperature: 0.6)
                
                var iterator = try TokenIterator(
                    input: prepared, model: modelContext.model, cache: modelContext.model.newCache(parameters: nil), parameters: params)
                var detokenizer = NaiveStreamingDetokenizer(tokenizer: modelContext.tokenizer)
                
                var outputText = ""
                let stopTokens = [
                    "<end_of_turn>",
                    "</end_of_turn>",
                    "<start_of_turn>",
                    "</start_of_turn>",
                    "<eos>",
                    "</s>",
                    "</completion>",
                    "<turn|>",
                    "<|channel>",
                    "thought"
                ]
                
                while let token = iterator.next() {
                    if Task.isCancelled { break }
                    detokenizer.append(token: token)
                    if let text = detokenizer.next() {
                        outputText += text
                        
                        var shouldStop = false
                        for stopToken in stopTokens {
                            if let range = outputText.range(of: stopToken) {
                                outputText = String(outputText[..<range.lowerBound])
                                shouldStop = true
                                break
                            }
                        }
                        if shouldStop { break }
                    }
                }
                

                return outputText
            } catch {
                print("[TypeFlow-Debug] LLMEngine smart replies error: \(error)")
                return ""
            }
        }
        
        // MLX.Memory.clearCache() moved inside lock
        
        var cleanResult = result
        if let range = cleanResult.range(of: "</completion>") {
            cleanResult = String(cleanResult[..<range.lowerBound])
        }
        
        let options = cleanResult.components(separatedBy: "|||")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        return Array(options.prefix(3))
    }
}
