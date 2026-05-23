import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// LLMEngine — Real on-device inference via MLXLLM
//
// SETUP REQUIRED:
// Before this compiles you must add the `mlx-swift-lm` Swift Package to the
// Xcode project:
//   File → Add Package Dependencies...
//   URL: https://github.com/ml-explore/mlx-swift-lm
//   Version: Up to Next Major (from 0.1.0)
//   Products to add to the TypeFlow target: MLXLLM, MLXLMCommon
//
// The first time `generateCompletion` is called it downloads the model
// (~1.5 GB for Gemma 3 1B 4-bit) into ~/Library/Caches/huggingface.
// Subsequent launches load from cache — no network needed.
// ─────────────────────────────────────────────────────────────────────────────

// Uncomment these imports after adding mlx-swift-lm in Xcode:
// import MLXLLM
// import MLXLMCommon

class LLMEngine {
    static let shared = LLMEngine()

    // Lazily-loaded model container — loaded once, reused on every completion.
    // Declared as Any? so the file compiles before mlx-swift-lm is added.
    private var modelContainer: Any?
    private var isLoading = false
    private var loadError: Error?

    private init() {
        // Kick off model load in the background so the first keystroke
        // doesn't block waiting for weights.
        Task { await loadModelIfNeeded() }
    }

    /// Generate a completion for the given prompt string.
    /// Returns empty string if the model isn't loaded yet or if inference fails.
    func generateCompletion(context: String) async -> String {
        // ── REAL INFERENCE ────────────────────────────────────────────────────
        // Uncomment the block below after adding mlx-swift-lm.
        //
        // await loadModelIfNeeded()
        //
        // guard let container = modelContainer as? ModelContainer else {
        //     return ""
        // }
        //
        // let result = try? await container.perform { context in
        //     let input = UserInput(prompt: context)
        //     let prepared = try await context.processor.prepare(input: input)
        //     let params = GenerateParameters(maxTokens: 30, temperature: 0.3)
        //     let output = try MLXLMCommon.generate(
        //         input: prepared,
        //         parameters: params,
        //         context: context
        //     ) { _ in }
        //     return output.output
        // }
        // return (result ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        //
        // ── END REAL INFERENCE ────────────────────────────────────────────────

        // Placeholder until mlx-swift-lm is linked.
        // This at least returns context-sensitive text instead of the hard-coded
        // word "completion" so basic injection can be validated.
        try? await Task.sleep(nanoseconds: 50_000_000)
        return generateHeuristicCompletion(for: context)
    }

    // ── Model loading (MLXLLM) ────────────────────────────────────────────────
    //
    // Uncomment this method body after adding mlx-swift-lm.
    //
    @MainActor
    private func loadModelIfNeeded() async {
        guard modelContainer == nil, !isLoading else { return }
        isLoading = true

        // import MLXLLM
        // import MLXLMCommon
        //
        // do {
        //     // Gemma 3 1B 4-bit ≈ 1.5 GB — fastest model that gives decent quality
        //     let config = LLMRegistry.gemma3_1B_qat_4bit
        //     let container = try await LLMModelFactory.shared.loadContainer(
        //         configuration: config
        //     ) { progress in
        //         print("[TypeFlow] Downloading model: \(Int(progress.fractionCompleted * 100))%")
        //     }
        //     self.modelContainer = container
        //     print("[TypeFlow] Model loaded: \(config.name)")
        // } catch {
        //     self.loadError = error
        //     print("[TypeFlow] Model load failed: \(error)")
        // }

        isLoading = false
    }

    // ── Heuristic fallback (used until real model is wired in) ────────────────
    //
    // Provides non-hardcoded completions by analysing the trailing context.
    // Delete this entire method once MLXLLM inference is enabled.
    private func generateHeuristicCompletion(for text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }

        // Common sentence starters
        let starters: [String: String] = [
            "I am ": "writing to you today",
            "I would like ": "to request",
            "Please ": "let me know if you have any questions.",
            "Thank you ": "for your time.",
            "Dear ": "team,",
            "The ": "following",
            "In ": "order to",
            "As ": "mentioned,",
            "We ": "would appreciate",
            "Could you ": "please",
        ]
        for (prefix, completion) in starters {
            if trimmed.hasSuffix(prefix.trimmingCharacters(in: .whitespaces)) {
                return completion
            }
        }

        // Guess at word completion from the last partial word
        let words = trimmed.components(separatedBy: .whitespaces)
        let lastWord = words.last ?? ""
        if lastWord.count >= 2 {
            let wordMap: [String: String] = [
                "ac": "cording to",
                "al": "though",
                "be": "cause",
                "co": "mplete",
                "de": "pending on",
                "ex": "ample",
                "fo": "llowing",
                "ge": "nerate",
                "ho": "wever",
                "im": "portant",
                "in": "formation",
                "pr": "obably",
                "re": "quested",
                "si": "milarly",
                "th": "erefore",
                "un": "fortunately",
            ]
            let key = String(lastWord.prefix(2).lowercased())
            if let suffix = wordMap[key], lastWord.count < 6 {
                return String(suffix.dropFirst(max(0, lastWord.count - 2)))
            }
        }

        return ""
    }
}
