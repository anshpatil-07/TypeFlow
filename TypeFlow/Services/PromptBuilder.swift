import Foundation
import Cocoa

class PromptBuilder {
    static let shared = PromptBuilder()
    
    // ── Frozen prefix cache ────────────────────────────────────────────────────
    // The system prefix (everything up to and including <start_of_turn>model\n)
    // MUST be byte-for-byte identical across every keystroke within the same
    // sentence so the MLX KV cache achieves the maximum LCP match and avoids
    // constant full-prefix re-evaluations.
    //
    // We freeze it after the first call and only invalidate when:
    //   • the active application changes  (appTitle changes)
    //   • the active line becomes empty   (new sentence started)
    //   • tone / personalization settings change
    private var frozenPrefix: String = ""
    private var frozenPrefixKey: String = ""   // app|tone|personalization|british

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
        return buildPromptPrefix(systemInstructions: systemInstructions)
    }
    
    /// Call this whenever the active app changes or the buffer is cleared so the
    /// frozen prefix will be regenerated on the next keystroke.
    func invalidateFrozenPrefix() {
        frozenPrefix = ""
        frozenPrefixKey = ""
        print("[TypeFlow-Debug] PromptBuilder: Frozen prefix invalidated.")
    }
    
    func buildPromptPrefix(systemInstructions: String) -> String {
        let context = UniversalContextManager.shared.latestContext
        let personalizationActive = SettingsManager.shared.personalizationEnabled
        let british = SettingsManager.shared.useBritishEnglish

        // Stable key: only changes when settings/app/screen change, NOT when the user types
        let screenHash = ScreenContextManager.shared.latestScreenText.hashValue
        let stableKey = "\(context.appTitle)|\(systemInstructions.hashValue)|\(personalizationActive)|\(british)|\(screenHash)"

        if frozenPrefixKey == stableKey && !frozenPrefix.isEmpty {
            // Return the frozen copy — guaranteed byte-for-byte identical
            return frozenPrefix
        }

        // ── Build fresh prefix ─────────────────────────────────────────────────
        // === TURN 1: User gives instructions ===
        var prompt = "<start_of_turn>user\n"
        prompt += "You are a real-time autocomplete engine. Use the following context to seamlessly finish the user's active line.\n"
        
        let currentScreen = ScreenContextManager.shared.latestScreenText
        prompt += "<screen_context>\n\(currentScreen)\n</screen_context>\n"
        
        let previousScreen = ScreenContextManager.shared.previousScreenText
        prompt += "<background_context>\n\(previousScreen)\n</background_context>\n"
        
        var extractedVocabulary = ""
        if personalizationActive {
            let vocab = VocabularyExtractor.shared.getVocabulary()
            if !vocab.isEmpty {
                extractedVocabulary = vocab.joined(separator: ", ")
            }
        }
        
        prompt += "Vocabulary: \(extractedVocabulary)"
        
        var finalInstructions = systemInstructions
        finalInstructions += "\nCRITICAL INSTRUCTION: Output only the exact text to continue the user's active line. Do not repeat instructions. If the context specifies a value, you MUST use that exact value."
        if british {
            finalInstructions += " Use British English spelling."
        }
        let lexicon = UserDefaults.standard.stringArray(forKey: "UserCustomLexicon") ?? []
        if !lexicon.isEmpty {
            finalInstructions += " NEVER alter: [\(lexicon.joined(separator: ", "))]."
        }
        prompt += " \(finalInstructions)<end_of_turn>\n"
        
        // === TURN 2: Model turn — activeLine is prefilled by buildPromptSuffix ===
        prompt += "<start_of_turn>model\n"
        prompt += "Continuing text seamlessly: "

        // Freeze and return
        frozenPrefix = prompt
        frozenPrefixKey = stableKey
        print("[TypeFlow-Debug] PromptBuilder: Prefix frozen (\(prompt.count) chars, key=\(stableKey.prefix(40))).")
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
        // CRITICAL: We MUST strip trailing whitespace before handing off to the tokeniser.
        // When the suffix ends with a space (word boundary), the Instruct model concludes
        // its turn is complete and immediately outputs \n<end_of_turn> with no actual text.
        // By ending on the last non-space character we force it to predict the next token.
        // The caller (generateCompletion) is responsible for prepending a space to the
        // result when the original textBeforeCaret ended in whitespace.
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
        
        // Strip trailing whitespace so the model's generation stream begins at the exact
        // last non-space character, preventing premature <end_of_turn> closure.
        return stableContext.trimmingCharacters(in: .init(charactersIn: " \t"))
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
