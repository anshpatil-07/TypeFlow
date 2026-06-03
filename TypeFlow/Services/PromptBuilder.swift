import Foundation

class PromptBuilder {
    static let shared = PromptBuilder()
    
    private init() {}
    
    func buildPrompt(textBeforeCaret: String, systemInstructions: String) -> String {
        let prefix = buildPromptPrefix(textBeforeCaret: textBeforeCaret, systemInstructions: systemInstructions)
        let suffix = buildPromptSuffix(textBeforeCaret: textBeforeCaret)
        return prefix + suffix
    }
    
    /// Builds the static portion of the prompt that does NOT change with the current text.
    /// This is what we prefill into the KV cache — it only changes when tone or
    /// personalization settings change, not when the user types a new sentence.
    func buildStaticPrefix(systemInstructions: String) -> String {
        var prompt = ""
        
        let personalizationActive = SettingsManager.shared.personalizationEnabled
        
        if personalizationActive {
            // Use recent samples without a text-specific filter so the prefix stays stable.
            let samples = TypingHistoryManager.shared.getRecentSamples(count: 3)
            if !samples.isEmpty {
                prompt += "[Past user writing samples]:\n"
                for sample in samples {
                    prompt += "- \(sample)\n"
                }
                prompt += "\n"
            }
            
            let vocab = VocabularyExtractor.shared.getVocabulary()
            if !vocab.isEmpty {
                let vocabStr = vocab.joined(separator: ", ")
                prompt += "[User vocabulary & jargon]:\n\(vocabStr)\n\n"
            }
        }
        
        prompt += "\(systemInstructions)\n\n"
        prompt += "[Current text to complete]:\n"
        return prompt
    }
    
    func buildPromptPrefix(textBeforeCaret: String, systemInstructions: String) -> String {
        var prompt = ""
        
        let personalizationActive = SettingsManager.shared.personalizationEnabled
        print("[TypeFlow-Debug] PromptBuilder: personalizationEnabled=\(personalizationActive)")
        
        if personalizationActive {
            let samples = TypingHistoryManager.shared.getRelevantSamples(for: textBeforeCaret, count: 3)
            print("[TypeFlow-Debug] PromptBuilder: matched \(samples.count) relevant writing samples")
            if !samples.isEmpty {
                prompt += "[Past user writing samples]:\n"
                for sample in samples {
                    prompt += "- \(sample)\n"
                }
                prompt += "\n"
            }
            
            let vocab = VocabularyExtractor.shared.getVocabulary()
            print("[TypeFlow-Debug] PromptBuilder: active vocabulary words count: \(vocab.count) (\(vocab))")
            if !vocab.isEmpty {
                let vocabStr = vocab.joined(separator: ", ")
                prompt += "[User vocabulary & jargon]:\n\(vocabStr)\n\n"
            }
        }
        
        prompt += "\(systemInstructions)\n\n"
        prompt += "[Current text to complete]:\n"
        return prompt
    }
    
    func buildPromptSuffix(textBeforeCaret: String) -> String {
        let contextText = String(textBeforeCaret.suffix(120))
        let trimmedContext = contextText.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(trimmedContext)\n\n<completion>"
    }
    
    func buildRewritePrompt(selectedText: String, systemInstructions: String, toneName: String) -> String {
        var prompt = ""
        prompt += "You are a writing assistant. Rewrite the following text to improve clarity, flow, and vocabulary while matching a \(toneName) tone.\n"
        prompt += "Instructions: \(systemInstructions)\n"
        prompt += "Do not write any intro, notes, explanations, or quotes. Output ONLY the rewritten text.\n\n"
        prompt += "[Text to Rewrite]:\n\(selectedText)\n\n"
        prompt += "<completion>"
        return prompt
    }
}
