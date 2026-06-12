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
        // === TURN 1: User gives instructions ===
        var prompt = "<start_of_turn>user\n"
        prompt += "You are a seamless text completion engine."
        
        let context = UniversalContextManager.shared.latestContext
        prompt += " Context: \(context.appTitle)"
        if !context.screenKeywords.isEmpty {
            prompt += ", \(context.screenKeywords.joined(separator: ", "))"
        }
        prompt += "."
        
        let personalizationActive = SettingsManager.shared.personalizationEnabled
        if personalizationActive {
            let vocab = VocabularyExtractor.shared.getVocabulary()
            if !vocab.isEmpty {
                prompt += " Vocabulary: \(vocab.joined(separator: ", "))."
            }
            let samples = TypingHistoryManager.shared.getRecentSamples(count: 2)
            if !samples.isEmpty {
                prompt += " Style: \(samples.joined(separator: " | "))."
            }
        }
        
        var finalInstructions = systemInstructions
        if SettingsManager.shared.useBritishEnglish {
            finalInstructions += " Use British English spelling."
        }
        let lexicon = UserDefaults.standard.stringArray(forKey: "UserCustomLexicon") ?? []
        if !lexicon.isEmpty {
            finalInstructions += " NEVER alter: [\(lexicon.joined(separator: ", "))]."
        }
        prompt += " \(finalInstructions)<end_of_turn>\n"
        
        // === TURN 2: Model turn — activeLine is prefilled here by buildPromptSuffix ===
        prompt += "<start_of_turn>model\n"
        
        return prompt
    }
    
    func hasClipboardTrigger(textBeforeCaret: String) -> Bool {
        let clipboardTriggers = AdaptivePatternLearner.shared.behaviors.clipboardTriggers
        let lowercasedText = textBeforeCaret.lowercased()
        return clipboardTriggers.contains { lowercasedText.hasSuffix($0) }
    }

    func buildPromptSuffix(textBeforeCaret: String) -> String {
        // The activeLine is placed INSIDE the model's response block (assistant pre-filling).
        // This makes the model believe it is mid-generation, causing it to naturally
        // continue the text rather than treating it as a new user question.
        //
        // CRITICAL: Nothing is appended after the activeLine. The stream must be physically
        // attached to the last character the user typed.
        let lines = textBeforeCaret.components(separatedBy: .newlines)
        let stableContext = lines.suffix(5).joined(separator: "\n")
        
        if hasClipboardTrigger(textBeforeCaret: textBeforeCaret) {
            let recentClipboard = Array(ClipboardMonitor.shared.recentItems.suffix(3))
            if !recentClipboard.isEmpty {
                let formattedClipboard = recentClipboard.enumerated()
                    .map { "\($0.offset + 1). \($0.element)" }
                    .joined(separator: "\n")
                return stableContext + "\n\nPaste the single most relevant clipboard item or the formatted list exactly as-is:\n" + formattedClipboard
            }
        }
        
        // Return with NO trailing newline, space, or control token — the model's stream
        // must begin immediately at the final typed character.
        return stableContext
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
