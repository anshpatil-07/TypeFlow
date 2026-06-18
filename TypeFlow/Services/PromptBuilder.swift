import Foundation
import Cocoa

/// Renders prompts for TypeFlow's llama.cpp inference pipeline.
///
/// Prompt format: ChatML (Gemma 4 / OpenHermes / Qwen family).
/// The model is wrapped in a strict instruct template so it acts as an
/// autocompleter rather than a document continuer. This prevents the native
/// echoing behaviour seen when feeding raw text to a base model.
///
/// Structure per request:
///   <|im_start|>system
///   [screen context lines + tone/spelling conditioning]
///   <|im_end|>
///   <|im_start|>user
///   [textBeforeCaret — the live field text]
///   <|im_end|>
///   <|im_start|>assistant
///   (model generates the inline continuation here)
///
/// The frozen-prefix cache covers the system turn, which is stable across
/// keystrokes within the same context window. Only the user turn (typed text)
/// changes per keystroke, keeping the llama KV-prefix reuse intact.
class PromptBuilder {
    static let shared = PromptBuilder()

    // MARK: - Frozen prefix cache
    // The static preface (screen context + conditioning lines) must be byte-for-byte identical
    // across keystrokes to maximise llama KV-prefix reuse. We freeze it after the first build
    // and invalidate only when the screen context, tone, or personalization settings change.
    private var frozenPrefix: String = ""
    private var frozenPrefixKey: String = ""

    private init() {
        let lexicon = UserDefaults.standard.stringArray(forKey: "UserCustomLexicon") ?? []
        for word in lexicon {
            NSSpellChecker.shared.learnWord(word)
        }
    }

    // MARK: - Public API

    /// Builds the full prompt passed to the LLM for inline completion.
    ///
    /// Structure (Cotabby base-model pattern):
    ///   [optional preface lines — tone, persona, screen context]
    ///   [blank line]
    ///   [caret prefix — trimmed to word boundary]
    ///
    /// The preface is character-budgeted so large screen captures never crowd out the live text.
    func buildPrompt(textBeforeCaret: String, liveBuffer: String, systemInstructions: String) -> String {
        let systemTurn = buildPromptPrefix(systemInstructions: systemInstructions)
        let userText   = buildPromptSuffix(textBeforeCaret: textBeforeCaret, liveBuffer: liveBuffer).text
        // Assemble the full ChatML prompt.
        // The assistant turn is left open (no <|im_end|>) so the model generates
        // the inline continuation directly without any wrapper token overhead.
        return systemTurn + "<|im_start|>user\n" + userText + "<|im_end|>\n<|im_start|>assistant\n"
    }

    /// Returns the frozen ChatML system turn for prewarm prefill.
    func buildStaticPrefix(systemInstructions: String) -> String {
        return buildPromptPrefix(systemInstructions: systemInstructions)
    }

    /// Call this when the active app or screen context changes so the frozen prefix
    /// is regenerated on the next keystroke.
    func invalidateFrozenPrefix() {
        frozenPrefix = ""
        frozenPrefixKey = ""
        print("[TypeFlow-Debug] PromptBuilder: Frozen prefix invalidated.")
    }

    // MARK: - Prefix builder — ChatML system turn (static, cacheable)
    //
    // Returns the full <|im_start|>system ... <|im_end|>\n block.
    // This is byte-for-byte stable across keystrokes within the same context
    // window, enabling llama KV-prefix reuse for all but the typed suffix.

    func buildPromptPrefix(systemInstructions: String) -> String {
        let british = SettingsManager.shared.useBritishEnglish
        let currentScreen = ScreenContextManager.shared.latestScreenText
        let context = UniversalContextManager.shared.latestContext

        // Stable cache key — invalidate when screen context, tone, spelling, or app changes.
        var historyHash = ""
        for snap in UniversalContextManager.shared.contextHistory {
            historyHash += "\(snap.appTitle)|\(snap.windowTitle ?? "nil")|\(snap.screenText.hashValue)|"
        }
        let stableKey = "\(historyHash)\(currentScreen.hashValue)|\(systemInstructions.hashValue)|\(british)|\(context.appBundleId)"

        if frozenPrefixKey == stableKey && !frozenPrefix.isEmpty {
            return frozenPrefix
        }

        // ── System turn content ───────────────────────────────────────────────
        // Build the lines that go inside the system role. We keep them short
        // and factual — the model treats these as privileged instructions that
        // shape its output without being echoed back.
        var systemLines: [String] = []

        // Core autocomplete directive — always present.
        systemLines.append("You are a real-time inline ghost-text autocompleter. Output ONLY the immediate inline continuation of the user's text. Never repeat or echo any part of the text provided by the user. Do not include markdown formatting, explanations, or any preamble.")

        // Tone / style line
        let isCode = isCodeEditor(bundleId: context.appBundleId, title: context.appTitle)
        if let style = makeStyleLine(systemInstructions: systemInstructions, british: british, isCode: isCode) {
            systemLines.append(style)
        }

        // Previous window screen context (dual-window: rolling history snapshot)
        let history = UniversalContextManager.shared.contextHistory
        if let snap = history.last, !snap.screenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var text = snap.screenText
            if text.count > 800 { text = String(text.prefix(800)) }
            systemLines.append("Nearby on screen: \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        // Current window screen context (live OCR snapshot)
        let trimmedScreen = currentScreen.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedScreen.isEmpty {
            var screen = trimmedScreen
            if screen.count > 800 { screen = String(screen.prefix(800)) }
            systemLines.append("Nearby on screen: \(screen)")
        }

        // Clipboard context
        let recentClip = ClipboardMonitor.shared.recentItems.last ?? ""
        let trimmedClip = recentClip.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedClip.isEmpty {
            let clipped = trimmedClip.count > 300 ? String(trimmedClip.prefix(300)) : trimmedClip
            systemLines.append("On the clipboard: \(clipped)")
        }

        // Assemble: wrap in ChatML system turn.
        let systemContent = systemLines.joined(separator: "\n")
        let systemTurn = "<|im_start|>system\n" + systemContent + "<|im_end|>\n"

        frozenPrefix = systemTurn
        frozenPrefixKey = stableKey
        print("[TypeFlow-Debug] PromptBuilder: System turn frozen (\(systemTurn.count) chars).")
        return systemTurn
    }

    // MARK: - Suffix builder — user turn content (live text, per-keystroke)
    //
    // Returns only the raw text that goes inside <|im_start|>user … <|im_end|>.
    // buildPrompt() wraps this in the correct ChatML user+assistant tokens.

    func buildPromptSuffix(textBeforeCaret: String, liveBuffer: String) -> (text: String, requiresHealing: Bool) {
        let lines = textBeforeCaret.components(separatedBy: .newlines)
        // Include up to 4 preceding lines for paragraph-level context
        let previousLines = lines.dropLast().suffix(4).joined(separator: "\n")
        let activeLine = lines.last ?? ""

        var suffix = ""
        if !previousLines.isEmpty {
            suffix += previousLines + "\n"
        }

        // Inline clipboard injection on trigger keyword
        if hasClipboardTrigger(textBeforeCaret: textBeforeCaret) {
            let recentClipboard = Array(ClipboardMonitor.shared.recentItems.suffix(3))
            if !recentClipboard.isEmpty {
                suffix += "\n" + recentClipboard.joined(separator: "\n") + "\n"
            }
        }

        var finalActiveLine = activeLine
        if !liveBuffer.isEmpty && finalActiveLine.hasSuffix(liveBuffer) {
            finalActiveLine = String(finalActiveLine.dropLast(liveBuffer.count))
        }
        finalActiveLine += liveBuffer

        // Trim trailing whitespace so generation begins at a clean word boundary.
        while finalActiveLine.hasSuffix(" ") || finalActiveLine.hasSuffix("\t") {
            finalActiveLine.removeLast()
        }

        // ── Token Healing ──────────────────────────────────────────────────────
        let wordBoundaryChars: Set<Character> = [
            " ", "\t", ".", "_", "(", ")", ":", "/", ",", ";",
            "{", "}", "=", "+", "-", "*", "&", "|", "!", "?",
            "\"", "'", "[", "]", "<", ">"
        ]
        let hasTrailingBoundary = finalActiveLine.last.map { wordBoundaryChars.contains($0) } ?? true

        var requiresHealing = false
        if !hasTrailingBoundary && !finalActiveLine.isEmpty {
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
                print("[TypeFlow-Debug] PromptBuilder: Token healing — partial word '\(partialWord)' at end of active line.")
            }
        }

        suffix += finalActiveLine
        return (text: suffix, requiresHealing: requiresHealing)
    }

    // MARK: - Rewrite prompt (instruction-following not needed for base models, but kept for future)

    func buildRewritePrompt(selectedText: String, systemInstructions: String, toneName: String) -> String {
        let british = SettingsManager.shared.useBritishEnglish
        var styleRules: [String] = []
        if !toneName.isEmpty && toneName.lowercased() != "neutral" {
            styleRules.append("Rewrite in a \(toneName) tone.")
        }
        if british {
            styleRules.append("Use British English spelling.")
        }
        let styleNote = styleRules.isEmpty ? "" : (styleRules.joined(separator: " ") + "\n")
        // Rewrite uses a minimal ChatML instruct format
        return "<|im_start|>system\n" +
               "You are a text rewriting assistant. " + styleNote +
               "Output ONLY the rewritten text. No explanations, no preamble.\n" +
               "<|im_end|>\n" +
               "<|im_start|>user\n" +
               selectedText + "\n" +
               "<|im_end|>\n" +
               "<|im_start|>assistant\n"
    }

    // MARK: - Private helpers

    /// Distills the ToneProfile's systemInstructions into a short style note
    /// suitable for inclusion inside the ChatML system turn.
    /// For code editors the style is prefixed with `//` so it reads as a comment
    /// inside any code block the model might complete.
    private func makeStyleLine(systemInstructions: String, british: Bool, isCode: Bool = false) -> String? {
        var rules: [String] = []

        let trimmed = systemInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let stripped = trimmed
                .replacingOccurrences(of: "Complete the text", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "Output only the next few words.", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "No explanation.", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "^[iI]n a\\s+", with: "", options: .regularExpression)
                .replacingOccurrences(of: "^[iI]n an?\\s+", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !stripped.isEmpty { rules.append(stripped) }
        }

        if british { rules.append("Use British English spelling.") }

        guard !rules.isEmpty else { return nil }
        let line = "Writing style: \(rules.joined(separator: " "))"
        return isCode ? "// \(line)" : line
    }

    // MARK: - Clipboard trigger helper (shared between prefix and suffix)

    func hasClipboardTrigger(textBeforeCaret: String) -> Bool {
        let clipboardTriggers = AdaptivePatternLearner.shared.behaviors.clipboardTriggers
        return clipboardTriggers.contains { textBeforeCaret.lowercased().hasSuffix($0) }
    }

    // MARK: - Code editor detection

    private func isCodeEditor(bundleId: String, title: String) -> Bool {
        let lowerTitle  = title.lowercased()
        let lowerBundle = bundleId.lowercased()
        let codeEditors = ["xcode", "vscode", "visual studio", "cursor", "intellij",
                           "pycharm", "webstorm", "android studio", "sublime",
                           "textmate", "nova", "bbedit", "zed", "iterm", "terminal",
                           "ghostty", "warp"]
        return codeEditors.contains {
            lowerTitle.contains($0) || lowerBundle.contains($0.replacingOccurrences(of: " ", with: ""))
        }
    }
}
