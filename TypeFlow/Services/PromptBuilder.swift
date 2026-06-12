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
        
        let context = UniversalContextManager.shared.latestContext
        prompt += "[System Context: Environment]\n"
        prompt += "Active App: \(context.appTitle)\n"
        if !context.screenKeywords.isEmpty {
            prompt += "Screen Keywords: \(context.screenKeywords.joined(separator: ", "))\n"
        }
        prompt += "\n"
        
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
        
        let context = UniversalContextManager.shared.latestContext
        prompt += "[System Context: Environment]\n"
        prompt += "Active App: \(context.appTitle)\n"
        if !context.screenKeywords.isEmpty {
            prompt += "Screen Keywords: \(context.screenKeywords.joined(separator: ", "))\n"
        }
        prompt += "\n"
        
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
        let clipboardTriggers = AdaptivePatternLearner.shared.behaviors.clipboardTriggers
        let lowercasedText = textBeforeCaret.lowercased()
        return clipboardTriggers.contains { lowercasedText.hasSuffix($0) }
    }

    func buildPromptSuffix(textBeforeCaret: String) -> String {
        // We give the model up to 5 lines of stable context. 
        // By splitting on newlines and taking a fixed number of lines, the leading string boundary 
        // NEVER shifts while the user is typing on the current line. This preserves LCP byte-alignment
        // perfectly, while giving the model enough document context to stay in "completion mode"
        // rather than falling back into "chat/markdown mode".
        let lines = textBeforeCaret.components(separatedBy: .newlines)
        let stableContext = lines.suffix(5).joined(separator: "\n")

        // DO NOT trim trailing whitespace! The LLM needs the exact trailing space or partial word
        // to natively predict the correct next token.
        // We also DO NOT append \n\n<completion> for normal typing, as that closes the text block
        // and forces the LLM to start a new formatted markdown response.
        var suffix = stableContext

        if hasClipboardTrigger(textBeforeCaret: textBeforeCaret) {
            let recentClipboard = Array(ClipboardMonitor.shared.recentItems.suffix(3))
            if !recentClipboard.isEmpty {
                let formattedClipboard = recentClipboard.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
                suffix += "\n\nCRITICAL INSTRUCTION: The user is triggering a clipboard paste. Here is their recent clipboard history:\n\(formattedClipboard)\nBased on their sentence, either paste the single most relevant item, or output the exact formatted list provided above. Do NOT invent or hallucinate any URLs or text not present in this list. CRITICAL: Output ONLY the clipboard item(s). Do NOT repeat the user's input phrase. Start your response directly with the clipboard text."
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
