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

class LLMEngine {
    static let shared = LLMEngine()

    // Lazily-loaded model container — loaded once, reused on every completion.
    private var modelContainer: ModelContainer?
    private var isLoading = false
    private var loadError: Error?

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
        print("[TypeFlow] Available memory check: \(availableBytes / 1024 / 1024) MB (Page size: \(pageSize) bytes)")
        
        return availableBytes >= twoGB
    }

    /// Generate a completion for the given text-before-caret.
    /// Uses the chat message API so the model's instruct chat template is applied,
    /// preventing the model from echoing the raw prompt tokens.
    func generateCompletion(textBeforeCaret: String, tone: String, customInstructions: String) async -> String {
        print("[TypeFlow-Debug] LLMEngine: generateCompletion called")
        await loadModelIfNeeded()
        
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
        
        // ── Build the chat messages ──────────────────────────────────────────
        // Minimal fill-in-the-blank prompt: [TEXT]___
        // Uses only the last 100 characters of user input.
        let contextText = String(textBeforeCaret.suffix(100))
        let prompt = "\(contextText)___"
        
        let messages: [Chat.Message] = [
            .user(prompt)
        ]
        
        print("[TypeFlow-Debug] LLMEngine: Input text: '\(textBeforeCaret)'")
        
        do {
            let result = try await container.perform { modelContext -> String in
                do {
                    print("[TypeFlow-Debug] LLMEngine: Preparing chat input...")
                    let input = UserInput(chat: messages)
                    let prepared = try await modelContext.processor.prepare(input: input)
                    print("[TypeFlow-Debug] LLMEngine: Input prepared. Starting generate stream...")
                    // maxTokens: 20 keeps completions short (2-5 words) and fast
                    let params = GenerateParameters(maxTokens: 20, temperature: 0.2)
                    let stream = try MLXLMCommon.generate(
                        input: prepared,
                        parameters: params,
                        context: modelContext
                    )
                    var outputText = ""
                    for await generation in stream {
                        if case .chunk(let text) = generation {
                            outputText += text
                            print("[TypeFlow-Debug] LLMEngine Chunk: '\(text)'")
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
            
            print("[TypeFlow-Debug] LLMEngine: Generation successful. Result: '\(result)'")
            return result.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            
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

        do {
            // Gemma 3 1B 4-bit ≈ 1.5 GB — fastest model that gives decent quality
            let config = LLMRegistry.gemma3_1B_qat_4bit
            self.modelContainer = try await #huggingFaceLoadModelContainer(configuration: config)
            print("[TypeFlow] Model loaded: \(config.name)")
        } catch {
            self.loadError = error
            print("[TypeFlow] Model load failed: \(error)")
        }

        isLoading = false
    }
}
