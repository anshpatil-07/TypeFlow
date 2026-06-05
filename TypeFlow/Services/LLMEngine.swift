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
// LLMEngine — Real on-device inference via MLXLLM
//
// The first time `generateCompletion` is called it downloads the model
// (~1.5 GB for Gemma 3 1B 4-bit) into ~/Library/Caches/huggingface.
// Subsequent launches load from cache — no network needed.
// ─────────────────────────────────────────────────────────────────────────────

struct KVCacheError: Error {
    let message: String
}

class LLMEngine {
    static let shared = LLMEngine()

    // Lazily-loaded model container — loaded once, reused on every completion.
    private var modelContainer: ModelContainer?
    private var isLoading = false
    private var loadError: Error?
    
    private var cachedPrefixPrompt: String?
    private var prefixLength = 0
    private var kvCache: [KVCache]?
    /// Stable cache key: tone-id + personalization flag, updated only when settings change.
    /// Changing the typing context (buffer clear) does NOT invalidate this key — only
    /// tone swaps or personalization toggle do, which actually alter the system prefix.
    private var cachedPrefixSettingsKey: String = ""
    private var inactivityTimer: Timer?
    
    var isModelReady: Bool { modelContainer != nil }
    
    private func resetInactivityTimer() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.inactivityTimer?.invalidate()
            self.inactivityTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                self.modelContainer = nil
                self.invalidateKVCache()
                print("[TypeFlow-Debug] LLMEngine: Model unloaded due to 5 minutes of inactivity")
            }
        }
    }
    
    /// Explicitly invalidate the KV cache — call only when tone or personalization changes.
    func invalidateKVCache() {
        kvCache = nil
        cachedPrefixPrompt = nil
        prefixLength = 0
        cachedPrefixSettingsKey = ""
        print("[TypeFlow-Debug] LLMEngine: KV cache explicitly invalidated (settings change)")
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
        // Commenting out repetitive log to avoid console spam on every keystroke
        // print("[TypeFlow] Available memory check: \(availableBytes / 1024 / 1024) MB (Page size: \(pageSize) bytes)")
        
        return availableBytes >= twoGB
    }
    
    /// Pre-warm the cache when the active app changes so zero-latency can be achieved
    func prewarmCache(toneProfile: ToneProfile) {
        print("[TypeFlow-Debug] LLMEngine: Pre-warming cache for tone \(toneProfile.name)")
        Task {
            await loadModelIfNeeded()
            resetInactivityTimer()
            
            guard let container = modelContainer else { return }
            guard checkMemoryStatus() else { return }
            
            do {
                _ = try await container.perform { [weak self] modelContext -> String in
                    guard let self = self else { return "" }
                    do {
                        let staticPrefixPrompt = PromptBuilder.shared.buildStaticPrefix(systemInstructions: toneProfile.systemInstructions)
                        let settingsKey = "\(toneProfile.name)|\(toneProfile.systemInstructions.hashValue)|\(SettingsManager.shared.personalizationEnabled)"
                        
                        if self.kvCache == nil || self.cachedPrefixPrompt != staticPrefixPrompt || self.cachedPrefixSettingsKey != settingsKey {
                            print("[TypeFlow-Debug] LLMEngine: Pre-warm cache miss — rebuilding static KV prefix...")
                            
                            let prefixInput = UserInput(prompt: staticPrefixPrompt)
                            let prefixPrepared = try await modelContext.processor.prepare(input: prefixInput)
                            let prefixTokens = prefixPrepared.text.tokens.asArray(Int.self)
                            
                            self.prefixLength = prefixTokens.count
                            self.cachedPrefixPrompt = staticPrefixPrompt
                            self.cachedPrefixSettingsKey = settingsKey
                            
                            let newCache = modelContext.model.newCache(parameters: nil)
                            let prefixMLXTokens = MLXArray(prefixTokens)
                            _ = modelContext.model(prefixMLXTokens[.newAxis], cache: newCache)
                            eval(newCache)
                            
                            self.kvCache = newCache
                            print("[TypeFlow-Debug] LLMEngine: Pre-warm complete with \(self.prefixLength) tokens.")
                        } else {
                            print("[TypeFlow-Debug] LLMEngine: Pre-warm cache hit — reusing KV prefix.")
                        }
                    } catch {
                        print("[TypeFlow-Debug] LLMEngine: Pre-warm Error in inner do block: \(error)")
                    }
                    return ""
                }
            } catch {
                print("[TypeFlow-Debug] LLMEngine: Pre-warm Error during container.perform: \(error)")
            }
        }
    }

    /// Generate a completion for the given text-before-caret.
    /// Uses the chat message API so the model's instruct chat template is applied,
    /// preventing the model from echoing the raw prompt tokens.
    func generateCompletion(textBeforeCaret: String, toneProfile: ToneProfile) async -> String {
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
        
        // Guard to cancel inference if available memory drops below 2GB
        guard checkMemoryStatus() else {
            print("[TypeFlow-Debug] LLMEngine: Low memory guard triggered! Cancelling generation.")
            return ""
        }
        
        do {
            let result = try await container.perform { [weak self] modelContext -> String in
                guard let self = self else { return "" }
                do {
                    // ── Build Prefix and Suffix prompts ──────────────────────────────
                    let suffixPrompt = PromptBuilder.shared.buildPromptSuffix(textBeforeCaret: textBeforeCaret)
                    let dynamicPrefixPrompt = PromptBuilder.shared.buildPromptPrefix(textBeforeCaret: textBeforeCaret, systemInstructions: toneProfile.systemInstructions)
                    
                    let fullPrompt = dynamicPrefixPrompt + suffixPrompt
                    let fullInput = UserInput(prompt: fullPrompt)
                    let fullPrepared = try await modelContext.processor.prepare(input: fullInput)
                    let fullTokens = fullPrepared.text.tokens.asArray(Int.self)
                    
                    // The KV-cache prefix uses ONLY static content (system instructions +
                    // personalization header) — NOT the current typed text. This means the
                    // cache is valid for the entire typing session unless tone or
                    // personalization settings actually change.
                    let staticPrefixPrompt = PromptBuilder.shared.buildStaticPrefix(systemInstructions: toneProfile.systemInstructions)
                    let settingsKey = "\(toneProfile.name)|\(toneProfile.systemInstructions.hashValue)|\(SettingsManager.shared.personalizationEnabled)"
                    
                    // Invalidate ONLY when tone/personalization settings change.
                    if self.kvCache == nil || self.cachedPrefixPrompt != staticPrefixPrompt || self.cachedPrefixSettingsKey != settingsKey {
                        print("[TypeFlow-Debug] LLMEngine: Cache miss — rebuilding static KV prefix (settings changed or first run)...")
                        
                        let prefixInput = UserInput(prompt: staticPrefixPrompt)
                        let prefixPrepared = try await modelContext.processor.prepare(input: prefixInput)
                        let prefixTokens = prefixPrepared.text.tokens.asArray(Int.self)
                        
                        // Find the common prefix tokens between the static prefix and full prompt
                        var common = [Int]()
                        for i in 0..<min(prefixTokens.count, fullTokens.count) {
                            if prefixTokens[i] == fullTokens[i] {
                                common.append(prefixTokens[i])
                            } else {
                                break
                            }
                        }
                        
                        self.prefixLength = common.count
                        self.cachedPrefixPrompt = staticPrefixPrompt
                        self.cachedPrefixSettingsKey = settingsKey
                        
                        // Instantiate a clean cache
                        let newCache = modelContext.model.newCache(parameters: nil)
                        
                        // Prefill the prefix tokens in the model
                        let prefixMLXTokens = MLXArray(common)
                        _ = modelContext.model(prefixMLXTokens[.newAxis], cache: newCache)
                        eval(newCache)
                        
                        self.kvCache = newCache
                        print("[TypeFlow-Debug] LLMEngine: KV cache prefilled with \(self.prefixLength) static tokens. Cache offset: \(newCache[0].offset)")
                    } else {
                        print("[TypeFlow-Debug] LLMEngine: Cache hit — reusing KV prefix (\(self.prefixLength) tokens).")
                    }
                    
                    guard let cache = self.kvCache else {
                        throw KVCacheError(message: "Failed to resolve KV cache")
                    }
                    
                    // Trim cache back to prefixLength
                    let tokensToTrim = cache[0].offset - self.prefixLength
                    if tokensToTrim > 0 {
                        print("[TypeFlow-Debug] LLMEngine: Trimming \(tokensToTrim) generated/suffix tokens from cache...")
                        trimPromptCache(cache, numTokens: tokensToTrim)
                        print("[TypeFlow-Debug] LLMEngine: Trim complete. Cache offset: \(cache[0].offset)")
                    }
                    
                    // Suffix tokens to evaluate are everything from prefixLength onwards
                    let suffixTokens = Array(fullTokens[self.prefixLength...])
                    let suffixInput = LMInput(tokens: MLXArray(suffixTokens))
                    
                    print("[TypeFlow-Debug] LLMEngine: Starting generate stream with suffix tokens count: \(suffixTokens.count)...")
                    let params = GenerateParameters(maxTokens: toneProfile.maxTokens, temperature: Float(toneProfile.temperature))
                    let stream = try MLXLMCommon.generate(
                        input: suffixInput,
                        cache: cache,
                        parameters: params,
                        context: modelContext
                    )
                    
                    var outputText = ""
                    for await generation in stream {
                        if case .chunk(let text) = generation {
                            outputText += text
                            print("[TypeFlow-Debug] LLMEngine Chunk: '\(text)'")
                            if outputText.contains("</completion>") {
                                print("[TypeFlow-Debug] LLMEngine: Found </completion> tag, stopping generation.")
                                break
                            }
                        }
                    }
                    print("[TypeFlow-Debug] LLMEngine: Stream finished. Total output: '\(outputText)'")
                    return outputText
                } catch {
                    print("[TypeFlow-Debug] LLMEngine Error in generation loop: \(error)")
                    throw error
                }
            }
            
            // Clear cached tensors after inference to release unified memory buffers
            MLX.Memory.clearCache()
            
            // Strip the closing tag if it exists
            var cleanResult = result
            if let range = cleanResult.range(of: "</completion>") {
                cleanResult = String(cleanResult[..<range.lowerBound])
            }
            
            var trimmedResult = cleanResult.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            
            // If the original text ended in a space, prepend space if the output doesn't start with one
            if textBeforeCaret.hasSuffix(" ") && !trimmedResult.isEmpty {
                if !trimmedResult.hasPrefix(" ") {
                    trimmedResult = " " + trimmedResult
                }
            }
            
            print("[TypeFlow-Debug] LLMEngine: Generation successful. Result: '\(trimmedResult)'")
            return trimmedResult
            
        } catch {
            print("[TypeFlow-Debug] LLMEngine Error during container.perform: \(error)")
            return ""
        }
    }

    // ── Model loading (MLXLLM) ────────────────────────────────────────────────
    
    @MainActor
    private func loadModelIfNeeded() async {
        guard modelContainer == nil, !isLoading else { return }
        isLoading = true
        NotificationCenter.default.post(name: Notification.Name("TypeFlowModelLoadingStateChanged"), object: true)

        do {
            // Gemma 3 4B 4-bit (Gemma 4 E2B) ≈ 3.2 GB
            let config = ModelConfiguration(
                id: "mlx-community/gemma-3-4b-it-qat-4bit",
                extraEOSTokens: ["<end_of_turn>"]
            )
            self.modelContainer = try await #huggingFaceLoadModelContainer(configuration: config)
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
        
        do {
            let result = try await container.perform { (modelContext: ModelContext) async throws -> String in
                let prompt = PromptBuilder.shared.buildRewritePrompt(
                    selectedText: selectedText,
                    systemInstructions: toneProfile.systemInstructions,
                    toneName: toneProfile.name
                )
                let input = UserInput(prompt: prompt)
                let prepared = try await modelContext.processor.prepare(input: input)
                
                let maxTokens = max(100, selectedText.count / 2)
                let params = GenerateParameters(maxTokens: maxTokens, temperature: Float(toneProfile.temperature))
                
                let stream = try MLXLMCommon.generate(
                    input: prepared,
                    cache: modelContext.model.newCache(parameters: nil),
                    parameters: params,
                    context: modelContext
                )
                
                var outputText = ""
                for await generation in stream {
                    if case .chunk(let text) = generation {
                        outputText += text
                        if outputText.contains("</completion>") {
                            break
                        }
                    }
                }
                return outputText
            }
            
            MLX.Memory.clearCache()
            
            var cleanResult = result
            if let range = cleanResult.range(of: "</completion>") {
                cleanResult = String(cleanResult[..<range.lowerBound])
            }
            return cleanResult.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        } catch {
            print("[TypeFlow-Debug] LLMEngine rewrite error: \(error)")
            return ""
        }
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
        
        do {
            let result = try await container.perform { (modelContext: ModelContext) async throws -> String in
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
                
                let stream = try MLXLMCommon.generate(
                    input: prepared,
                    cache: modelContext.model.newCache(parameters: nil),
                    parameters: params,
                    context: modelContext
                )
                
                var outputText = ""
                for await generation in stream {
                    if case .chunk(let text) = generation {
                        outputText += text
                        if outputText.contains("</completion>") {
                            break
                        }
                    }
                }
                return outputText
            }
            
            MLX.Memory.clearCache()
            
            var cleanResult = result
            if let range = cleanResult.range(of: "</completion>") {
                cleanResult = String(cleanResult[..<range.lowerBound])
            }
            
            let options = cleanResult.components(separatedBy: "|||")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            
            return Array(options.prefix(3))
        } catch {
            print("[TypeFlow-Debug] LLMEngine smart replies error: \(error)")
            return []
        }
    }
}
