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
        let textBeforeCaret = textBeforeCaret.replacingOccurrences(of: "\u{00A0}", with: " ")
        let liveBuffer = liveBuffer.replacingOccurrences(of: "\u{00A0}", with: " ")
        let profile = ModelProfile.current()
        if profile.promptMode == .fim {
            let (contextPrefix, clipboardIncluded, ocrIncluded, ctxIncluded, fimOcrSnippet) = buildPromptPrefix(textBeforeCaret: textBeforeCaret, systemInstructions: systemInstructions, policy: policy)
            let (fimBounded, truncated, len, lines) = buildBoundedFIMPrefix(textBeforeCaret: textBeforeCaret, liveBuffer: liveBuffer, policy: policy)
            
            // Append the per-keystroke OCR snippet (if relevant) to the FIM context prefix.
            var enrichedContextPrefix = contextPrefix
            if !fimOcrSnippet.isEmpty {
                let snippet = fimOcrSnippet.trimmingCharacters(in: .whitespacesAndNewlines)
                let ocrBlock = "Nearby on screen: \(snippet)"
                enrichedContextPrefix = enrichedContextPrefix.isEmpty ? ocrBlock : enrichedContextPrefix + "\n" + ocrBlock
            }
            
            let finalPrefix = enrichedContextPrefix.isEmpty ? fimBounded : "\(enrichedContextPrefix)\n\n\(fimBounded)"
            
            if let workID = workID {
                LatencyInstrumentation.shared.setPromptMetrics(requestID: requestID, workID: workID, boundedLen: len, lineCount: lines, suffixLen: 0, truncated: truncated, trailingPreserved: fimBounded.last?.isWhitespace ?? false, mode: "fim")
            }
            
            print("[TypeFlow-Debug] FIM Context: rawLen=\(textBeforeCaret.count) boundedLen=\(len) lines=\(lines) truncated=\(truncated) trailingSpacePreserved=\(fimBounded.last?.isWhitespace ?? false)")
            let _ = (clipboardIncluded, ocrIncluded, ctxIncluded)  // suppress unused warnings
            
            let suffix = ""
            
            return "\(profile.fimPrefix ?? "")\(finalPrefix)\(profile.fimSuffix ?? "")\(suffix)\(profile.fimMiddle ?? "")"
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
                let prefix = buildPromptPrefix(textBeforeCaret: textBeforeCaret, systemInstructions: systemInstructions, policy: .inlineActiveTextOnly).text
                let suffix = buildPromptSuffix(textBeforeCaret: textBeforeCaret, liveBuffer: liveBuffer, policy: .inlineActiveTextOnly).text
                return prefix + suffix
            }
        }
        
        let prefixResult = buildPromptPrefix(textBeforeCaret: textBeforeCaret, systemInstructions: systemInstructions, policy: policy)
        let suffix = buildPromptSuffix(textBeforeCaret: textBeforeCaret, liveBuffer: liveBuffer, policy: policy).text
        // Append the per-keystroke OCR snippet immediately before the typed suffix so the LLM
        // sees relevant on-screen context just before the active line. This is not frozen.
        let ocrInfix: String
        if !prefixResult.ocrSnippet.isEmpty {
            let snippet = prefixResult.ocrSnippet.trimmingCharacters(in: .whitespacesAndNewlines)
            ocrInfix = "Nearby on screen: \(snippet)\n\n"
        } else {
            ocrInfix = ""
        }
        return prefixResult.text + ocrInfix + suffix
    }

    /// Returns the frozen conditioning preface for prewarm prefill.
    func buildStaticPrefix(systemInstructions: String) -> String {
        return buildPromptPrefix(textBeforeCaret: "", systemInstructions: systemInstructions, policy: .fullContext).text
    }

    /// Call this when the active app or screen context changes so the frozen prefix
    /// is regenerated on the next keystroke.
    func invalidateFrozenPrefix() {
        frozenPrefix = ""
        frozenPrefixKey = ""
        print("[TypeFlow-Debug] PromptBuilder: Frozen prefix invalidated.")
    }
    
    // MARK: - FIM Context Builder
    
    private func buildBoundedFIMPrefix(textBeforeCaret: String, liveBuffer: String, policy: AutocompleteContextPolicy) -> (String, Bool, Int, Int) {
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
        
        if policy != .inlineActiveTextOnly {
        
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

    func buildPromptPrefix(textBeforeCaret: String, systemInstructions: String, policy: AutocompleteContextPolicy = .fullContext) -> (text: String, clipboardIncluded: Bool, ocrIncluded: Bool, universalContextIncluded: Bool, ocrSnippet: String) {
        let british = SettingsManager.shared.useBritishEnglish
        let context = UniversalContextManager.shared.latestContext
        let recentClip = ClipboardMonitor.shared.recentItems.last ?? ""

        let activeLine = textBeforeCaret.components(separatedBy: .newlines).last ?? ""
        let trimmedActive = activeLine.trimmingCharacters(in: .whitespacesAndNewlines)

        var ocrSnippet = ""
        var screenUsed = false
        var screenReason = "notRelevant"
        var screenChars = 0
        var screenRawChars = 0
        var screenCacheAgeMs = 0.0
        var screenExtractionMs = 0.0
        var screenActiveInputExcluded = true
        var promptCharsAdded = 0

        let rawScreen: String
        let screenSource: String

        if ScreenContextManager.testingMode {
            rawScreen = ScreenContextManager.shared.latestScreenText
            screenSource = "OCR"
        } else if let cached = ScreenContextManager.shared.cachedContext {
            rawScreen = cached.text
            screenSource = cached.source
            screenRawChars = cached.rawCharCount
            screenExtractionMs = cached.extractionMs
            screenCacheAgeMs = Date().timeIntervalSince(cached.timestamp) * 1000.0
        } else {
            rawScreen = ScreenContextManager.shared.latestScreenText
            screenSource = "OCR"
        }
        let currentScreen = rawScreen.replacingOccurrences(of: "\u{00A0}", with: " ")
        if screenRawChars == 0 { screenRawChars = currentScreen.count }

        // Screen context stopwords: common words that do not prove topical relevance.
        let screenStopWords: Set<String> = [
            "the", "and", "is", "in", "it", "to", "of", "a", "that", "on", "for", "with",
            "as", "by", "this", "or", "are", "be", "from", "at", "an", "was", "but", "not",
            "you", "he", "she", "they", "we", "i", "my", "his", "her", "our", "its", "can",
            "will", "would", "have", "has", "had", "do", "did", "been", "being", "if", "so",
            "up", "out", "use", "get", "than", "then", "also", "just", "like", "into", "more"
        ]

        if policy != .inlineActiveTextOnly && !currentScreen.isEmpty && !trimmedActive.isEmpty {
            let lowerActive = trimmedActive.lowercased()
            let lowerScreen = currentScreen.lowercased()

            // Define search ranges excluding the active line itself to prevent self-matching.
            // AX traversal already excludes the focused input field, so for AX sources we
            // search the full extracted text. For OCR, exclude the region matching the typed text.
            var searchRanges: [Range<String.Index>] = []
            if screenSource == "OCR", let activeLineRange = lowerScreen.range(of: lowerActive, options: .backwards) {
                if activeLineRange.lowerBound > lowerScreen.startIndex {
                    searchRanges.append(lowerScreen.startIndex..<activeLineRange.lowerBound)
                }
                if activeLineRange.upperBound < lowerScreen.endIndex {
                    searchRanges.append(activeLineRange.upperBound..<lowerScreen.endIndex)
                }
            } else {
                searchRanges.append(lowerScreen.startIndex..<lowerScreen.endIndex)
            }

            func findMatchRange(of target: String) -> Range<String.Index>? {
                for range in searchRanges {
                    if let mRange = lowerScreen.range(of: target, range: range) {
                        return mRange
                    }
                }
                return nil
            }

            // Extract meaningful (non-stopword) keywords from what the user is typing.
            let activeWords = lowerActive
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 3 && !screenStopWords.contains($0) }

            var matchRange: Range<String.Index>? = nil

            // 1. Longest suffix matching: find the longest suffix of lowerActive (up to 100 chars, down to 6 chars) that exists in lowerScreen
            let maxSuffixLen = min(lowerActive.count, 100)
            if maxSuffixLen >= 6 {
                for len in stride(from: maxSuffixLen, through: 6, by: -1) {
                    let suffix = String(lowerActive.suffix(len))
                    if let range = findMatchRange(of: suffix) {
                        matchRange = range
                        screenReason = "longestSuffixMatch(len=\(len))"
                        break
                    }
                }
            }

            // 2. Heuristic keyword matches when direct suffix matching yields nothing
            if matchRange == nil {
                // Check two-keyword phrase overlap
                if activeWords.count >= 2 {
                    let twoWordPhrase = activeWords.suffix(2).joined(separator: " ")
                    if let range = findMatchRange(of: twoWordPhrase) {
                        matchRange = range
                        screenReason = "twoKeywordOverlap"
                    }
                }

                // Single meaningful keyword overlap (≥4 chars to catch short technical terms)
                if matchRange == nil, let lastMeaningfulWord = activeWords.last(where: { $0.count >= 4 }) {
                    if let range = findMatchRange(of: lastMeaningfulWord) {
                        matchRange = range
                        screenReason = "singleKeywordOverlap"
                    }
                }

                // Multi-keyword relevance (at least 2 out of N meaningful keywords)
                if matchRange == nil && activeWords.count >= 3 {
                    let hits = activeWords.filter { word in
                        for range in searchRanges {
                            if lowerScreen.range(of: word, range: range) != nil {
                                return true
                            }
                        }
                        return false
                    }
                    if hits.count >= 2 {
                        if let firstHit = hits.first,
                           let range = findMatchRange(of: firstHit) {
                            matchRange = range
                            screenReason = "multiKeywordRelevance(\(hits.count)of\(activeWords.count))"
                        }
                    }
                }
            }

            if let range = matchRange {
                // Build a centered snippet: up to 200 chars before the match + up to 300 chars after
                // This gives a 200–500 char window around the relevant passage.
                let matchStart = range.lowerBound
                let preStart = currentScreen.index(matchStart, offsetBy: -min(200, currentScreen.distance(from: currentScreen.startIndex, to: matchStart)), limitedBy: currentScreen.startIndex) ?? currentScreen.startIndex
                let snippetEnd = currentScreen.index(matchStart, offsetBy: 300, limitedBy: currentScreen.endIndex) ?? currentScreen.endIndex
                ocrSnippet = String(currentScreen[preStart..<snippetEnd])
                screenUsed = true
                screenChars = ocrSnippet.count
                promptCharsAdded = screenChars
            }
        }

        var clipboardUsed = false
        var clipSnippet = ""

        if policy != .inlineActiveTextOnly && !recentClip.isEmpty && !trimmedActive.isEmpty && trimmedActive.count >= 6 {
            let lowerActive = trimmedActive.lowercased()
            let clipWords = lowerActive
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 5 }
            var matchRange: Range<String.Index>? = nil

            if let meaningfulWord = clipWords.last, let range = recentClip.range(of: meaningfulWord, options: .caseInsensitive) {
                matchRange = range
            }

            if let range = matchRange {
                let start = range.lowerBound
                let end = recentClip.index(start, offsetBy: 200, limitedBy: recentClip.endIndex) ?? recentClip.endIndex
                clipSnippet = String(recentClip[start..<end])
                clipboardUsed = true
            }
        }

        var historyHash = ""
        for snap in UniversalContextManager.shared.contextHistory {
            historyHash += "\(snap.appTitle)|\(snap.windowTitle ?? "nil")|"
        }
        // Exclude per-keystroke screenUsed/screenChars from the stableKey so that the frozen prefix
        // is not invalidated every keystroke. Screen snippets are per-request, not per-context-window.
        let stableKey = "\(policy.rawValue)|\(historyHash)\(systemInstructions.hashValue)|\(british)|\(context.appBundleId)|\(clipboardUsed)"

        var universalContextIncluded = false

        if policy != .inlineActiveTextOnly {
            let history = UniversalContextManager.shared.contextHistory
            if let snap = history.last, !snap.screenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                universalContextIncluded = true
            }
        }

        // Estimate prompt token count: rough 4-char-per-token heuristic
        let promptTokenEstimate = (screenChars + trimmedActive.count) / 4
        print("[ScreenContextDiagnostic] screenContextAvailable=\(!currentScreen.isEmpty) screenContextUsed=\(screenUsed) screenContextChars=\(screenChars) screenContextSource=\(screenSource) screenContextReason=\(screenReason) previousContextIncluded=\(policy == .fullContext) previousContextOmittedReason=none pageContextAvailable=\(!currentScreen.isEmpty) pageContextSource=\(screenSource) pageContextCharsRaw=\(screenRawChars) pageContextCharsUsed=\(screenChars) pageContextUsed=\(screenUsed) activeInputExcluded=\(screenActiveInputExcluded) extractionMs=\(String(format: "%.1f", screenExtractionMs)) cacheAgeMs=\(String(format: "%.0f", screenCacheAgeMs)) promptCharsAdded=\(promptCharsAdded) promptTokenEstimate=\(promptTokenEstimate)")

        if frozenPrefixKey == stableKey && !frozenPrefix.isEmpty {
            // Return the cached prefix, but still attach the freshly computed ocrSnippet
            // so the caller can inject it into the per-keystroke suffix.
            return (frozenPrefix, clipboardUsed, screenUsed, universalContextIncluded, screenUsed ? ocrSnippet : "")
        }

        var prefaceLines: [String] = []

        let isCode = isCodeEditor(bundleId: context.appBundleId, title: context.appTitle)
        if let style = makeStyleLine(systemInstructions: systemInstructions, british: british, isCode: isCode) {
            prefaceLines.append(style)
        }

        if policy != .inlineActiveTextOnly {
            let history = UniversalContextManager.shared.contextHistory
            if let snap = history.last, !snap.screenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                var text = snap.screenText
                // Cap to 300 chars to avoid OCR noise dominating the prompt.
                if text.count > 300 { text = String(text.prefix(300)) }
                prefaceLines.append("Nearby on screen: \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
            }

            // NOTE: ocrSnippet is intentionally NOT added here.
            // It is per-keystroke (depends on active-line keywords) and must not be frozen.
            // The caller receives it as a separate return value and appends it to the suffix.

            if clipboardUsed && !clipSnippet.isEmpty {
                prefaceLines.append("On the clipboard: \(clipSnippet.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }

        let built: String
        if prefaceLines.isEmpty {
            built = ""
        } else {
            let joined = prefaceLines.joined(separator: "\n")
            if isCode {
                built = "/* System Context:\n\(joined)\n*/\n\n"
            } else {
                built = "――― System Context ―――\n\(joined)\n――――――――――――――――――――――\n\n"
            }
        }

        frozenPrefix = built
        frozenPrefixKey = stableKey
        print("[TypeFlow-Debug] PromptBuilder: Conditioning preface frozen (\(built.count) chars, \(prefaceLines.count) blocks).")
        return (built, clipboardUsed, screenUsed, universalContextIncluded, screenUsed ? ocrSnippet : "")
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
