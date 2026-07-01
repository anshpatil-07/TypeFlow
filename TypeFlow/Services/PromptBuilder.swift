import Foundation
import Cocoa

/// Renders prompts for TypeFlow's llama.cpp inference pipeline.
///
/// Prompt format: Base Model (Cotabby BaseCompletionPromptRenderer architecture)
/// Base models have no instruction-following channel and will echo "Task:" scaffolding
/// verbatim into ghost text. This renderer treats the model as a pure text continuer.
///
/// Structure per request (5-block layout):
///   [1] Writing style / tone conditioning   ← stable, cached, KV-reused
///   [2] Dual-window rolling history ("Nearby on screen: …")
///   [3] Live OCR & clipboard context
///   \n\n                                    ← blank-line separator (no label the model can copy)
///   [4] Trimmed typing prefix              ← per-keystroke suffix (only this changes the KV state)
///
/// The preface (blocks 1–3) is frozen per context window via `frozenPrefix`; only block 4
/// changes on each keystroke, giving the LLM maximum KV prefix reuse.
enum AutocompleteContextPolicy: String {
    case inlineActiveTextOnly
    case fullContext
}

class PromptBuilder {
    static let shared = PromptBuilder()

    // MARK: - Frozen prefix cache
    // The static preface must be byte-for-byte identical across keystrokes to maximise
    // llama KV-prefix reuse. We freeze it after the first build and invalidate only when
    // the screen context, tone, clipboard, or personalisation settings change.
    private var frozenPrefix: String = ""
    private var frozenPrefixKey: String = ""

    private init() {
        let lexicon = UserDefaults.standard.stringArray(forKey: "UserCustomLexicon") ?? []
        for word in lexicon {
            NSSpellChecker.shared.learnWord(word)
        }
    }

    private func contextAuditPreview(_ text: String, limit: Int = 220) -> String {
        let escaped = text
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
        if escaped.count <= limit { return escaped }
        return "..." + String(escaped.suffix(limit))
    }

    private func logContextAudit(_ message: String) {
        print("[TypeFlow-ContextAudit] \(message)")
    }

    // MARK: - Public API

    /// Builds the full prompt passed to the LLM for inline completion.
    func buildPrompt(textBeforeCaret: String, liveBuffer: String, systemInstructions: String, policy: AutocompleteContextPolicy = .fullContext) -> String {
        let prefix = buildPromptPrefix(systemInstructions: systemInstructions, policy: policy).text
        let suffix = buildPromptSuffix(textBeforeCaret: textBeforeCaret, liveBuffer: liveBuffer, policy: policy).text
        return prefix + suffix
    }

    /// Returns the frozen conditioning preface for prewarm prefill.
    func buildStaticPrefix(systemInstructions: String) -> String {
        return buildPromptPrefix(systemInstructions: systemInstructions, policy: .fullContext).text
    }

    /// Call this when the active app or screen context changes so the frozen prefix
    /// is regenerated on the next keystroke.
    func invalidateFrozenPrefix() {
        frozenPrefix = ""
        frozenPrefixKey = ""
        print("[TypeFlow-Debug] PromptBuilder: Frozen prefix invalidated.")
    }

    // MARK: - Prefix builder — base model conditioning preface (static, cacheable)
    //
    // Returns the conditioning block: style lines + dual-window screen context + clipboard,
    // followed by \n\n. This entire block is stable across keystrokes within the same
    // context window, enabling llama KV-prefix reuse for all but the typed suffix.
    //
    // There are NO <start_of_turn> / <end_of_turn> / instruct wrappers here. Base models
    // treat those as literal document text and will echo them, causing hallucination.

    func buildPromptPrefix(systemInstructions: String, policy: AutocompleteContextPolicy = .fullContext) -> (text: String, clipboardIncluded: Bool, ocrIncluded: Bool, universalContextIncluded: Bool) {
        let british = SettingsManager.shared.useBritishEnglish
        let context = UniversalContextManager.shared.latestContext
        let currentScreen = ScreenContextManager.shared.latestScreenText
        let recentClip = ClipboardMonitor.shared.recentItems.last ?? ""

        // Stable cache key — invalidate when tone, spelling, app, screen text, or clipboard changes.
        var historyHash = ""
        for snap in UniversalContextManager.shared.contextHistory {
            historyHash += "\(snap.appTitle)|\(snap.windowTitle ?? "nil")|"
        }
        let screenHash = String(currentScreen.prefix(200))
        let clipHash   = String(recentClip.prefix(100))
        let stableKey  = "\(policy.rawValue)|\(historyHash)\(systemInstructions.hashValue)|\(british)|\(context.appBundleId)|\(screenHash)|\(clipHash)"

        var clipboardIncluded = false
        var ocrIncluded = false
        var universalContextIncluded = false

        // In this refactor we don't cache the boolean flags to keep it simple, but we can compute them inline for return.
        // But since we want to return them, let's bypass cache or recompute the bools for the cache hit. 
        // Actually, let's just always compute the bools even on cache hit, it's cheap.

        if policy != .inlineActiveTextOnly {
            let history = UniversalContextManager.shared.contextHistory
            if let snap = history.last, !snap.screenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                universalContextIncluded = true
            }
            let trimmedScreen = currentScreen.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedScreen.isEmpty {
                ocrIncluded = true
            }
            let trimmedClip = recentClip.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedClip.isEmpty {
                clipboardIncluded = true
            }
        }

        if frozenPrefixKey == stableKey && !frozenPrefix.isEmpty {
            return (frozenPrefix, clipboardIncluded, ocrIncluded, universalContextIncluded)
        }

        // ── Block 1: Style / persona conditioning ─────────────────────────────
        // "Writing style: <rules>." – base model conditions on this description;
        // it does not obey commands, so imperative phrasing is intentionally absent.
        var prefaceLines: [String] = []

        let isCode = isCodeEditor(bundleId: context.appBundleId, title: context.appTitle)
        if let style = makeStyleLine(systemInstructions: systemInstructions, british: british, isCode: isCode) {
            prefaceLines.append(style)
        }

        if policy != .inlineActiveTextOnly {
            // ── Block 2: Dual-window rolling history (previous window screen text) ──
            let history = UniversalContextManager.shared.contextHistory
            if let snap = history.last, !snap.screenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                var text = snap.screenText
                if text.count > 800 { text = String(text.prefix(800)) }
                prefaceLines.append("Nearby on screen: \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
            }

        // ── Block 3: Live OCR snapshot ────────────────────────────────────────
        let trimmedScreen = currentScreen.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedScreen.isEmpty {
            var screen = trimmedScreen
            if screen.count > 800 { screen = String(screen.prefix(800)) }
            prefaceLines.append("Nearby on screen: \(screen)")
        }

        // ── Block 4: Clipboard context ────────────────────────────────────────
        let trimmedClip = recentClip.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedClip.isEmpty {
            let clipped = trimmedClip.count > 300 ? String(trimmedClip.prefix(300)) : trimmedClip
            prefaceLines.append("On the clipboard: \(clipped)")
        }
        }

        // ── Final preface: joined with \n, then \n\n boundary before the live prefix ──
        // The blank-line separator isolates the conditioning context from the live text
        // without a label the model could copy — exactly as in Cotabby's renderer.
        let built: String
        if prefaceLines.isEmpty {
            // No context: the suffix will be handed to the model bare. We still emit an
            // empty string so the suffix is appended directly (no leading separator).
            built = ""
        } else {
            built = prefaceLines.joined(separator: "\n") + "\n\n"
        }

        frozenPrefix = built
        frozenPrefixKey = stableKey
        print("[TypeFlow-Debug] PromptBuilder: Conditioning preface frozen (\(built.count) chars, \(prefaceLines.count) blocks).")
        return (built, clipboardIncluded, ocrIncluded, universalContextIncluded)
    }

    // MARK: - Suffix builder — live typing prefix (per-keystroke)
    //
    // Returns the raw text that goes at the very end of the prompt, after \n\n.
    // Trailing whitespace is trimmed so generation begins at a clean word boundary,
    // matching BaseCompletionPromptRenderer.trimmingTrailingWhitespace().

    func buildPromptSuffix(textBeforeCaret: String, liveBuffer: String, policy: AutocompleteContextPolicy = .fullContext) -> (text: String, requiresHealing: Bool, clipboardIncluded: Bool) {
        let lines = textBeforeCaret.components(separatedBy: .newlines)
        // Include up to 4 preceding lines for paragraph-level context
        let previousLines = lines.dropLast().suffix(4).joined(separator: "\n")
        let activeLine = lines.last ?? ""
        logContextAudit("PromptBuilder input textBeforeCaretLen=\(textBeforeCaret.count) textBeforeCaret='\(contextAuditPreview(textBeforeCaret))' liveBufferLen=\(liveBuffer.count) liveBuffer='\(contextAuditPreview(liveBuffer))' previousLinesLen=\(previousLines.count) activeLineLen=\(activeLine.count) activeLine='\(contextAuditPreview(activeLine))'")

        var suffix = ""
        if !previousLines.isEmpty {
            suffix += previousLines + "\n"
        }

        var clipboardIncluded = false
        // Inline clipboard injection on trigger keyword
        if policy != .inlineActiveTextOnly && hasClipboardTrigger(textBeforeCaret: textBeforeCaret) {
            let recentClipboard = Array(ClipboardMonitor.shared.recentItems.suffix(3))
            if !recentClipboard.isEmpty {
                suffix += "\n" + recentClipboard.joined(separator: "\n") + "\n"
                clipboardIncluded = true
            }
        }

        // `textBeforeCaret` is canonicalized before it reaches PromptBuilder.
        // Do not append `liveBuffer` here; doing so creates a second merge site
        // and can duplicate or corrupt the cursor context.
        var finalActiveLine = activeLine

        // Trim trailing whitespace so generation begins at a clean word boundary.
        // This is the BaseCompletionPromptRenderer.trimmingTrailingWhitespace() equivalent.
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
        logContextAudit("PromptBuilder output suffixLen=\(suffix.count) finalActiveLineLen=\(finalActiveLine.count) requiresHealing=\(requiresHealing) suffix='\(contextAuditPreview(suffix))'")
        return (text: suffix, requiresHealing: requiresHealing, clipboardIncluded: clipboardIncluded)
    }

    // MARK: - Rewrite prompt
    // Rewrite uses a minimal base-model instruction format (no Gemma instruct tokens).

    func buildRewritePrompt(selectedText: String, systemInstructions: String, toneName: String) -> String {
        let british = SettingsManager.shared.useBritishEnglish
        var styleRules: [String] = []
        if !toneName.isEmpty && toneName.lowercased() != "neutral" {
            styleRules.append("Rewrite in a \(toneName) tone.")
        }
        if british {
            styleRules.append("Use British English spelling.")
        }
        if !systemInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            styleRules.append(systemInstructions.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        // Base model rewrite: conditioning preface + blank line + text block.
        // No instruct wrappers; the model continues from "Rewritten:" as a natural label.
        var lines: [String] = []
        lines.append("Rewrite the following text exactly once. Output only the rewritten text.")
        if !styleRules.isEmpty {
            lines.append("Writing style: \(styleRules.joined(separator: " "))")
        }
        let preface = lines.joined(separator: "\n")
        return preface + "\n\nOriginal: \(selectedText)\n\nRewritten: "
    }

    // MARK: - Private helpers

    /// Distills the ToneProfile's systemInstructions into a short style note
    /// suitable for inclusion in the base-model conditioning preface.
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

    // MARK: - Clipboard trigger helper

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
