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
    
    func buildPrompt(textBeforeCaret: String, liveBuffer: String, systemInstructions: String) -> String {
        let prefix = buildPromptPrefix(systemInstructions: systemInstructions)
        let suffixResult = buildPromptSuffix(textBeforeCaret: textBeforeCaret, liveBuffer: liveBuffer)
        return prefix + suffixResult.text
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
        var historyHash = ""
        for snap in UniversalContextManager.shared.contextHistory {
            historyHash += "\(snap.appTitle)|\(snap.windowTitle ?? "nil")|\(snap.screenText.hashValue)|"
        }
        let currentScreen = ScreenContextManager.shared.latestScreenText
        let stableKey = "\(historyHash)\(context.appTitle)|\(systemInstructions.hashValue)|\(personalizationActive)|\(british)|\(currentScreen.hashValue)"

        if frozenPrefixKey == stableKey && !frozenPrefix.isEmpty {
            // Return the frozen copy — guaranteed byte-for-byte identical
            return frozenPrefix
        }

        // ── Build fresh prefix ─────────────────────────────────────────────────
        var prompt = "<start_of_turn>user\n"
        prompt += "You are an inline autocomplete engine. Output ONLY the immediate trailing characters to complete the user's final word or line. Do not output chat markers, 'User:', or markdown formatting.\n\n"
        
        let history = UniversalContextManager.shared.contextHistory
        
        // Print exactly one previous history block to avoid duplication
        if let snap = history.last {
            prompt += "=== Previous Screen Context ===\n"
            prompt += "[Application: \(snap.appTitle)"
            if let window = snap.windowTitle {
                prompt += " | Window: \(window)"
            }
            prompt += "]\n"
            
            var text = snap.screenText
            if text.count > 3500 {
                text = String(text.prefix(3500)) + "...\n[Context Truncated]"
            }
            
            prompt += "\(text)\n======================\n\n"
        }
        
        let isBrowser = ["zen", "safari", "chrome", "brave", "edge", "arc"].contains { context.appTitle.lowercased().contains($0) || context.appBundleId.lowercased().contains($0) }
        
        prompt += "=== Active Screen Context ===\n"
        prompt += "[Application: \(context.appTitle)"
        if isBrowser, let windowTitle = context.windowTitle {
            prompt += " | Window: \(windowTitle)"
        }
        prompt += "]\n"
        prompt += "\(currentScreen)\n======================\n\n"
        

        
        var finalInstructions = systemInstructions
        finalInstructions += "\nCRITICAL INSTRUCTIONS:\n1. Output the text to continue the user's active line naturally. You may adapt or slightly paraphrase the surrounding context to ensure grammatical continuity with the user's specific prefix, but prioritize using exact vocabulary from the context where possible.\n2. If the active line refers to or asks for a magic constant, hex value, variable, or key, immediately output the literal constant or identifier from the context.\n3. When completing code statements or loops, always reference collections/variables by name using their exact property (such as '.count' without parentheses, e.g. 'user_elements.count', NOT 'user_elements.count()') instead of evaluating their literal values or sizes.\n4. When completing C-style for-loops, use post-increment 'i++' instead of pre-increment '++i', e.g. 'i++' (NOT '++i').\n5. If the context contains file paths, line numbers, hex constants, variable names, or specific identifiers, reproduce them character-for-character exactly as they appear in the context."
        if british {
            finalInstructions += " Use British English spelling."
        }

        prompt += "Instructions: \(finalInstructions)\n\n"
        
        prompt += "[Text to Complete]\n"
        
        let appName = context.appTitle.lowercased()
        let bundleId = context.appBundleId.lowercased()
        let codeEditors = ["xcode", "code", "cursor", "intellij", "android studio", "sublime text", "nova", "zed", "pycharm", "webstorm"]
        let isCodeEditor = codeEditors.contains { appName.contains($0) || bundleId.contains($0) }
        
        if isCodeEditor {
            prompt += "```python\n"
        } else {
            // Prose mode: emit NO backticks to prevent standard sentence structure from being misparsed
        }

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

    func buildPromptSuffix(textBeforeCaret: String, liveBuffer: String) -> (text: String, requiresHealing: Bool) {
        let lines = textBeforeCaret.components(separatedBy: .newlines)
        let previousLines = lines.dropLast().suffix(4).joined(separator: "\n")
        let activeLine = lines.last ?? ""
        
        var suffix = ""
        if !previousLines.isEmpty {
            suffix += previousLines + "\n"
        }
        
        if hasClipboardTrigger(textBeforeCaret: textBeforeCaret) {
            let recentClipboard = Array(ClipboardMonitor.shared.recentItems.suffix(3))
            if !recentClipboard.isEmpty {
                let formattedClipboard = recentClipboard.enumerated()
                    .map { "\($0.offset + 1). \($0.element)" }
                    .joined(separator: "\n")
                suffix += "\nPaste the single most relevant clipboard item or the formatted list exactly as-is:\n" + formattedClipboard + "\n"
            }
        }
        
        // Close the user's turn and start the model's turn
        suffix += "<end_of_turn>\n<start_of_turn>model\n"
        
        var finalActiveLine = activeLine
        if !liveBuffer.isEmpty && finalActiveLine.hasSuffix(liveBuffer) {
            finalActiveLine = String(finalActiveLine.dropLast(liveBuffer.count))
        }
        finalActiveLine += liveBuffer
        
        // Strip trailing whitespace so the model's generation stream begins at the exact
        // last non-space character, preventing premature <end_of_turn> closure.
        // We MUST preserve leading whitespace so the model maintains indentation context!
        while finalActiveLine.hasSuffix(" ") || finalActiveLine.hasSuffix("\t") {
            finalActiveLine.removeLast()
        }
        
        // ── Token Healing ──────────────────────────────────────────────────────
        // If the line ends in a dangling partial word (no trailing word-boundary
        // character after the last boundary), inject a [PARTIAL:] hint so the
        // model knows it MUST continue from that exact character sequence and
        // cannot skip ahead or re-emit the leading letters as a new token.
        let wordBoundaryChars: Set<Character> = [" ", "\t", ".", "_", "(", ")", ":", "/", ",", ";", "{", "}", "=", "+", "-", "*", "&", "|", "!", "?", "\"", "'", "[", "]", "<", ">"]
        let hasTrailingBoundary = finalActiveLine.last.map { wordBoundaryChars.contains($0) } ?? true
        
        var requiresHealing = false
        if !hasTrailingBoundary && !finalActiveLine.isEmpty {
            // Find the dangling partial: everything after the last word-boundary char
            var partialStart = finalActiveLine.endIndex
            var idx = finalActiveLine.index(before: finalActiveLine.endIndex)
            while idx >= finalActiveLine.startIndex {
                if wordBoundaryChars.contains(finalActiveLine[idx]) {
                    partialStart = finalActiveLine.index(after: idx)
                    break
                }
                if idx == finalActiveLine.startIndex {
                    partialStart = finalActiveLine.startIndex
                    break
                }
                idx = finalActiveLine.index(before: idx)
            }
            let partialWord = String(finalActiveLine[partialStart...])
            if !partialWord.isEmpty {
                requiresHealing = true
                print("[TypeFlow-Debug] PromptBuilder: Token healing — partial word '\(partialWord)' detected at end of active line.")
            }
        }
        
        suffix += finalActiveLine
        
        return (text: suffix, requiresHealing: requiresHealing)
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
