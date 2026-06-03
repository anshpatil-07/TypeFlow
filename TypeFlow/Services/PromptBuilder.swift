import Foundation

class PromptBuilder {
    static let shared = PromptBuilder()
    
    private init() {}
    
    func buildPrompt(textBeforeCaret: String) -> String {
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
        
        prompt += "Complete the text. Output only the next few words. No explanation.\n\n"
        
        let contextText = String(textBeforeCaret.suffix(120))
        prompt += "[Current text to complete]:\n\(contextText)\n\n<completion>"
        
        return prompt
    }
}
