import Foundation
import Cocoa

class PromptBuilder {
    static let shared = PromptBuilder()
    
    private init() {
        let lexicon = UserDefaults.standard.stringArray(forKey: "UserCustomLexicon") ?? []
        for word in lexicon {
            NSSpellChecker.shared.learnWord(word)
        }
    }
    
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
                prompt += "[Passive Stylistic Vocabulary Influence]:\n\(vocabStr)\n\n"
            }
        }
        
        var finalInstructions = systemInstructions
        if SettingsManager.shared.useBritishEnglish {
            finalInstructions += " Always use British English spelling (e.g., colour, prioritise)."
        }
        
        let lexicon = UserDefaults.standard.stringArray(forKey: "UserCustomLexicon") ?? []
        let protectedWords = lexicon.isEmpty ? "" : " NEVER alter these exact user-specific words: [\(lexicon.joined(separator: ", "))]."
        
        finalInstructions += " CRITICAL: You are an invisible autocomplete engine. DO NOT recite, list, or explicitly mention the provided vocabulary words. Only use them naturally if they flawlessly fit the immediate grammatical context of the suffix. Prioritize the user's document context above all else.\(protectedWords)"
        
        prompt += "[System Instructions]:\n\(finalInstructions)\n\n"
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
                prompt += "[Passive Stylistic Vocabulary Influence]:\n\(vocabStr)\n\n"
            }
        }
        
        var finalInstructions = systemInstructions
        if SettingsManager.shared.useBritishEnglish {
            finalInstructions += " Always use British English spelling (e.g., colour, prioritise)."
        }
        
        let lexicon = UserDefaults.standard.stringArray(forKey: "UserCustomLexicon") ?? []
        let protectedWords = lexicon.isEmpty ? "" : " NEVER alter these exact user-specific words: [\(lexicon.joined(separator: ", "))]."
        
        finalInstructions += " CRITICAL: You are an invisible autocomplete engine. DO NOT recite, list, or explicitly mention the provided vocabulary words. Only use them naturally if they flawlessly fit the immediate grammatical context of the suffix. Prioritize the user's document context above all else.\(protectedWords)"
        
        prompt += "[System Instructions]:\n\(finalInstructions)\n\n"
        prompt += "[Current text to complete]:\n"
        return prompt
    }
    
    func buildPromptSuffix(textBeforeCaret: String) -> String {
        let contextText = String(textBeforeCaret.suffix(120))
        let trimmedContext = contextText.trimmingCharacters(in: .whitespacesAndNewlines)

        var suffix = "\(trimmedContext)\n\n<completion>"

        // Inject recent clipboard items if the caret text ends with a clipboard-seeking phrase
        let clipboardTriggers = [
            "here is the link:",
            "here is the url:",
            "my email is",
            "my email address is",
            "the code is",
            "the snippet is",
            "paste it:",
            "the link is",
            "the url is",
            "contact me at",
        ]
        let lowercasedText = textBeforeCaret.lowercased().trimmingCharacters(in: .whitespaces)
        let hasClipboardTrigger = clipboardTriggers.contains { lowercasedText.hasSuffix($0) }

        if hasClipboardTrigger {
            let items = ClipboardMonitor.shared.recentItems
            if !items.isEmpty {
                let clipboardContext = items.enumerated()
                    .map { "- \($0.element)" }
                    .joined(separator: "\n")
                suffix = "\(trimmedContext)\n\n[Recent Clipboard Items]:\n\(clipboardContext)\n\n<completion>"
            }
        }

        return suffix
    }
    
    func buildRewritePrompt(selectedText: String, systemInstructions: String, toneName: String) -> String {
        var prompt = ""
        prompt += "You are a writing assistant. Rewrite the following text to improve clarity, flow, and vocabulary while matching a \(toneName) tone.\n"
        var finalInstructions = systemInstructions
        if SettingsManager.shared.useBritishEnglish {
            finalInstructions += " Always use British English spelling (e.g., colour, prioritise)."
        }
        prompt += "Instructions: \(finalInstructions)\n"
        prompt += "Do not write any intro, notes, explanations, or quotes. Output ONLY the rewritten text.\n\n"
        prompt += "[Text to Rewrite]:\n\(selectedText)\n\n"
        prompt += "<completion>"
        return prompt
    }
}
