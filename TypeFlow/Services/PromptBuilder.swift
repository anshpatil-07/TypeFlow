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

enum InlinePromptMode: String {
    case baseActiveLine
    case cleanProsePreface
    case fewShotInline
    case cleanLocalSentence
    case hybridFewShot
    case baseActiveLineWithMinimalComment
    case suffixOnlyBase
    case disabledInstructionWrapper
    case fim
}

class PromptBuilder {
    static let shared = PromptBuilder()
    
    var afterSpacePromptMode: InlinePromptMode {
        if let saved = UserDefaults.standard.string(forKey: "AfterSpacePromptMode"),
           let mode = InlinePromptMode(rawValue: saved) {
            return mode
        }
        return .baseActiveLine
    }

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
    func buildPrompt(textBeforeCaret: String, liveBuffer: String, systemInstructions: String, requestID: UInt64? = nil, workID: UInt64? = nil, policy: AutocompleteContextPolicy = .fullContext) -> String {
        let profile = ModelProfile.current()
        
        if profile.promptMode == .fim {
            // FIM production path: Bounded context, NO OCR, NO clipboard.
            let (prefix, truncated, len, lines) = buildBoundedFIMPrefix(textBeforeCaret: textBeforeCaret, liveBuffer: liveBuffer)
            
            if let workID = workID {
                LatencyInstrumentation.shared.setPromptMetrics(requestID: requestID, workID: workID, boundedLen: len, lineCount: lines, suffixLen: 0, truncated: truncated, trailingPreserved: prefix.last?.isWhitespace ?? false, mode: "fim")
            }
            
            print("[TypeFlow-Debug] FIM Context: rawLen=\(textBeforeCaret.count) boundedLen=\(len) lines=\(lines) truncated=\(truncated) trailingSpacePreserved=\(prefix.last?.isWhitespace ?? false)")
            
            // FIM suffix: text after caret (currently not passed to buildPrompt, but we could pass it if available)
            // For now, suffix is empty, as we only have textBeforeCaret and liveBuffer.
            let suffix = ""
            
            return "\(profile.fimPrefix ?? "")\(prefix)\(profile.fimSuffix ?? "")\(suffix)\(profile.fimMiddle ?? "")"
        }
        
        let lines = textBeforeCaret.components(separatedBy: .newlines)
        let activeLine = lines.last ?? ""
        let activeLineEndsWithWhitespace = activeLine.hasSuffix(" ") || activeLine.hasSuffix("\t") || activeLine.hasSuffix("\n")
        
        if activeLineEndsWithWhitespace {
            print("[TypeFlow-Debug] PromptBuilder: Using \(afterSpacePromptMode.rawValue) prompt for after-space")
            switch afterSpacePromptMode {
            case .fim: return ""
            case .disabledInstructionWrapper:
                return """
                <start_of_turn>user
                You are an inline autocomplete engine. Continue the following line of text exactly where it leaves off.
                Do not repeat the input. Do not explain. Do not use conversational filler, quotes, or markdown. Output only the short natural continuation (2-8 words).
                
                Text to continue:
                \(activeLine)<end_of_turn>
                <start_of_turn>model
                """
            case .baseActiveLine, .cleanLocalSentence:
                return activeLine
            case .cleanProsePreface:
                return "Continue the text naturally. Return only the next few words.\n\n\(activeLine)"
            case .fewShotInline:
                return """
                Input: the quick brown 
                Output: fox jumped
                Input: i want the ghost text to feel natural 
                Output: and useful
                Input: this completion should be useful because 
                Output: it predicts the next words
                Input: \(activeLine)
                Output: 
                """
            case .hybridFewShot:
                return """
                Input: the quick brown 
                Output: fox jumped
                Input: \(activeLine)
                Output: 
                """
            case .baseActiveLineWithMinimalComment:
                return """
                Continue the text naturally. Output only the continuation.

                \(activeLine)
                """
            case .suffixOnlyBase:
                let prefix = buildPromptPrefix(systemInstructions: systemInstructions, policy: .inlineActiveTextOnly).text
                let suffix = buildPromptSuffix(textBeforeCaret: textBeforeCaret, liveBuffer: liveBuffer, policy: .inlineActiveTextOnly).text
                return prefix + suffix
            }
        }
        
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
    
    // MARK: - FIM Context Builder
    
    private func buildBoundedFIMPrefix(textBeforeCaret: String, liveBuffer: String) -> (String, Bool, Int, Int) {
        var mergedText = textBeforeCaret
        if !liveBuffer.isEmpty {
            let components = mergedText.components(separatedBy: "\t")
            if components.count > 1, components.last?.isEmpty == true {
                mergedText = components.dropLast().joined(separator: "\t") + liveBuffer
            }
        }
        
        let charCap = 512
        let lineCap = 10
        
        let allLines = mergedText.components(separatedBy: .newlines)
        
        // Always include the active line
        let activeLine = allLines.last ?? ""
        
        var prefixLines: [String] = [activeLine]
        var currentLen = activeLine.count
        var truncated = false
        
        // Iterate backwards from the second-to-last line
        for i in stride(from: allLines.count - 2, through: 0, by: -1) {
            let line = allLines[i]
            // +1 for the newline character that joins them
            if prefixLines.count >= lineCap {
                truncated = true
                break
            }
            if currentLen + line.count + 1 > charCap {
                truncated = true
                break
            }
            prefixLines.insert(line, at: 0)
            currentLen += line.count + 1
        }
        
        // Exact reconstruction with newlines to preserve trailing whitespace and formatting
        let boundedPrefix = prefixLines.joined(separator: "\n")
        return (boundedPrefix, truncated, boundedPrefix.count, prefixLines.count)
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
        let activeLine = lines.last ?? ""
        
        var previousLinesIncluded = 0
        var previousContextLen = 0
        var previousContextOmittedReason = "none"
        var finalPreviousLines = ""
        
        if policy == .inlineActiveTextOnly {
            // Active-line first policy
            // 1. Grab at most 1 previous non-empty line
            if let lastNonEmpty = lines.dropLast().last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                // Check if it's too long
                if lastNonEmpty.count > 160 {
                    previousContextOmittedReason = "tooLong"
                } else if activeLine.count > 20 {
                    // Prefer active line only if we have enough prose context
                    previousContextOmittedReason = "activeLineOnly"
                } else {
                    let hasNumberedList = lastNonEmpty.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil
                    let activeHasNumberedList = activeLine.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil
                    
                    if hasNumberedList && !activeHasNumberedList {
                        previousContextOmittedReason = "numberedListMismatch"
                    } else if lastNonEmpty.lowercased().contains("the quick brown") || lastNonEmpty.lowercased().contains("twinkle") || lastNonEmpty.lowercased().contains("ok ill overlook") {
                        previousContextOmittedReason = "repeatPhraseRisk"
                    } else {
                        finalPreviousLines = lastNonEmpty
                        previousLinesIncluded = 1
                        previousContextLen = finalPreviousLines.count
                    }
                }
            }
        } else {
            // Full context policy (up to 4 lines)
            let prev = lines.dropLast().suffix(4)
            finalPreviousLines = prev.joined(separator: "\n")
            previousLinesIncluded = prev.count
            previousContextLen = finalPreviousLines.count
        }
        
        logContextAudit("PromptBuilder input textBeforeCaretLen=\(textBeforeCaret.count) textBeforeCaret='\(contextAuditPreview(textBeforeCaret))' liveBufferLen=\(liveBuffer.count) liveBuffer='\(contextAuditPreview(liveBuffer))' previousLinesLen=\(finalPreviousLines.count) activeLineLen=\(activeLine.count) activeLine='\(contextAuditPreview(activeLine))'")

        var suffix = ""
        if !finalPreviousLines.isEmpty {
            suffix += finalPreviousLines + "\n"
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
        
        let activeLineEndsWithWhitespace = activeLine.hasSuffix(" ") || activeLine.hasSuffix("\t") || activeLine.hasSuffix("\n")
        var requiresHealing = false
        var partialWord = ""
        var mode = "empty"

        if activeLine.isEmpty {
            mode = "empty"
        } else if activeLineEndsWithWhitespace {
            mode = "afterSpace"
            requiresHealing = false
        } else {
            let wordBoundaryChars: Set<Character> = [
                " ", "\t", ".", "_", "(", ")", ":", "/", ",", ";",
                "{", "}", "=", "+", "-", "*", "&", "|", "!", "?",
                "\"", "'", "[", "]", "<", ">"
            ]
            let hasTrailingBoundary = wordBoundaryChars.contains(activeLine.last!)
            
            if hasTrailingBoundary {
                mode = "punctuation"
                requiresHealing = false
            } else {
                mode = "midWord"
                var partialStart = activeLine.endIndex
                var idx = activeLine.index(before: activeLine.endIndex)
                while idx >= activeLine.startIndex {
                    if wordBoundaryChars.contains(activeLine[idx]) {
                        partialStart = activeLine.index(after: idx)
                        break
                    }
                    if idx == activeLine.startIndex {
                        partialStart = activeLine.startIndex
                        break
                    }
                    idx = activeLine.index(before: idx)
                }
                partialWord = String(activeLine[partialStart...])
                if !partialWord.isEmpty {
                    requiresHealing = true
                }
            }
        }
        
        // Ensure we don't trim trailing whitespace!
        suffix += finalActiveLine
        
        let suffixPreservesTrailingSpace = activeLineEndsWithWhitespace && (suffix.hasSuffix(" ") || suffix.hasSuffix("\t") || suffix.hasSuffix("\n"))
        let trailingSpaceTrimmed = activeLineEndsWithWhitespace && !suffixPreservesTrailingSpace
        
        let promptSuffixLineCount = suffix.components(separatedBy: .newlines).count
        
        print("[PromptBuilderMode] mode=\(mode) activeLineEndsWithWhitespace=\(activeLineEndsWithWhitespace) requiresHealing=\(requiresHealing) partialWord='\(partialWord)' suffixPreservesTrailingSpace=\(suffixPreservesTrailingSpace) violation=\(trailingSpaceTrimmed ? "trailingSpaceTrimmed" : "none")")
        print("[PromptContextWindow] policy=\(policy == .inlineActiveTextOnly ? "activeLineFirst" : "fullContext") activeLineLen=\(activeLine.count) previousContextLen=\(previousContextLen) previousLinesIncluded=\(previousLinesIncluded) previousContextOmittedReason=\(previousContextOmittedReason) promptSuffixLineCount=\(promptSuffixLineCount)")
        
        if policy == .inlineActiveTextOnly && promptSuffixLineCount > 2 {
            print("[PromptContextWindow] warning=tooManyLinesForInlineAutocomplete")
        }

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
