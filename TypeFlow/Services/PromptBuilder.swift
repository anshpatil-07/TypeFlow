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
        let prefix = buildPromptPrefix(systemInstructions: systemInstructions)
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
    
    func buildPromptPrefix(systemInstructions: String) -> String {
        var prompt = ""
        
        let personalizationActive = SettingsManager.shared.personalizationEnabled
        print("[TypeFlow-Debug] PromptBuilder: personalizationEnabled=\(personalizationActive)")
        
        if personalizationActive {
            // Use recent samples without a text-specific filter. Filtering dynamically based on 
            // the user's active typing completely shifts the prompt text on every keystroke,
            // instantly breaking the LLM's KV Cache LCP alignment.
            let samples = TypingHistoryManager.shared.getRecentSamples(count: 3)
            print("[TypeFlow-Debug] PromptBuilder: injecting \(samples.count) static writing samples")
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
    
    func hasClipboardTrigger(textBeforeCaret: String) -> Bool {
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
            "link: ",
            "link:",
            "url: ",
            "code: "
        ]
        let lowercasedText = textBeforeCaret.lowercased()
        return clipboardTriggers.contains { lowercasedText.hasSuffix($0) }
    }

    func buildPromptSuffix(textBeforeCaret: String) -> String {
        // Strict active-line isolation. 
        // A sliding character window pulls in leading newlines that shift on every keystroke, 
        // which completely breaks the LLM's LCP (Longest Common Prefix) KV cache byte-alignment.
        // We only pass the currently active line the user is typing on.
        let activeLine = textBeforeCaret.components(separatedBy: .newlines).last ?? ""
        let trimmedContext = activeLine.trimmingCharacters(in: .whitespacesAndNewlines)

        var suffix = "\(trimmedContext)\n\n<completion>"

        if hasClipboardTrigger(textBeforeCaret: textBeforeCaret) {
            let recentClipboard = Array(ClipboardMonitor.shared.recentItems.suffix(3))
            if !recentClipboard.isEmpty {
                let formattedClipboard = recentClipboard.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
                suffix = "\(trimmedContext)\n\nCRITICAL INSTRUCTION: The user is triggering a clipboard paste. Here is their recent clipboard history:\n\(formattedClipboard)\nBased on their sentence, either paste the single most relevant item, or output the exact formatted list provided above. Do NOT invent or hallucinate any URLs or text not present in this list. CRITICAL: Output ONLY the clipboard item(s). Do NOT repeat the user's input phrase. Start your response directly with the clipboard text.\n\n<completion>"
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
