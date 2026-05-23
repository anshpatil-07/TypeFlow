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

    /// Generate a completion for the given prompt string.
    /// Returns empty string if the model isn't loaded yet or if inference fails.
    func generateCompletion(context: String) async -> String {
        await loadModelIfNeeded()
        
        guard let container = modelContainer else {
            return ""
        }
        
        // Guard to cancel inference if available memory drops below 2GB
        guard checkMemoryStatus() else {
            print("[TypeFlow] Low memory guard triggered! Cancelling generation.")
            return ""
        }
        
        print("[TypeFlow] Generating completion for prompt: \(context)")
        let result = try? await container.perform { modelContext in
            do {
                let input = UserInput(prompt: context)
                let prepared = try await modelContext.processor.prepare(input: input)
                let params = GenerateParameters(maxTokens: 30, temperature: 0.3)
                let stream = try MLXLMCommon.generate(
                    input: prepared,
                    parameters: params,
                    context: modelContext
                )
                var outputText = ""
                for await generation in stream {
                    if case .chunk(let text) = generation {
                        outputText += text
                        print("[TypeFlow] Chunk: \(text)")
                    }
                }
                return outputText
            } catch {
                print("[TypeFlow] Error in generation loop: \(error)")
                throw error
            }
        }
        
        // Clear cached tensors after inference to release unified memory buffers
        MLX.Memory.clearCache()
        
        print("[TypeFlow] Generation result: \(result ?? "nil")")
        return (result ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
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
