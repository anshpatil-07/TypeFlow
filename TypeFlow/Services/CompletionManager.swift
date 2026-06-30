import Cocoa

class CompletionManager: @unchecked Sendable {
    static let shared = CompletionManager()
    
    var currentCompletion: String?
    weak var accessibilityMonitor: AccessibilityMonitor?
    weak var overlayWindowController: OverlayWindowController?
    
    var isOverlayVisible: Bool {
        return overlayWindowController?.overlayWindow.isVisible ?? false
    }
    
    private let workController = SuggestionWorkController()
    
    /// Tracks the timestamp of the most recent keystroke for adaptive debounce.
    private var lastKeystrokeTime: Date = .distantPast
    
    private var pendingCompletionRequest: String?
    private var activeSpellCorrection: (misspelled: String, corrected: String)?
    private var activeSnippetKey: String?
    var activeRewriteText: String?
    var activeRewritePID: pid_t?
    var activeRewriteApp: NSRunningApplication?
    var activeSmartReplyPID: pid_t?
    private var rewriteTask: Task<Void, Never>?
    
    var isSuppressedUntilNextTyping = false
    private var lastBufferSnapshot: String = ""
    private var generationStartCaretText: String = ""
    private let resultOwnershipLock = NSLock()
    private var latestResultRequestID: UInt64 = 0
    private var staleCompletedGenerationDiscardCount: UInt64 = 0
    private var staleVisibleUpdateAttemptCount: UInt64 = 0
    private let generationCancellationLock = NSLock()
    private var activeGenerationCancellationToken: LlamaGenerationCancellationToken?

    private struct ResultOwnershipSnapshot {
        let latestResultRequestID: UInt64
        let generationResultRequestID: UInt64
        let workID: UInt64
        let currentWorkID: UInt64
        let staleCompletedGenerationDiscardCount: UInt64
        let staleVisibleUpdateAttemptCount: UInt64
    }

    private struct PredictionSnapshot {
        let rawTextBeforeCaret: String
        let source: TextBeforeCaretSource
        let liveBuffer: String
    }

    private struct CanonicalPredictionContext {
        let canonicalTextBeforeCaret: String
        let liveBufferForPrompt: String
        let didAppendLiveBuffer: Bool
        let appendReason: String

        var activeLine: String {
            canonicalTextBeforeCaret.components(separatedBy: .newlines).last ?? ""
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

    private func canonicalizePredictionSnapshot(_ snapshot: PredictionSnapshot) -> CanonicalPredictionContext {
        let rawText = snapshot.rawTextBeforeCaret
        let liveBuffer = snapshot.liveBuffer

        var canonicalText = rawText
        var didAppend = false
        var reason = ""

        switch snapshot.source {
        case .keystrokeBufferFallback:
            reason = "source is keystrokeBufferFallback; fallback is already complete best-known cursor text"
        case .providedText:
            reason = "source is providedText; explicit caller text is already canonical"
        case .none:
            if rawText.isEmpty && !liveBuffer.isEmpty {
                canonicalText = liveBuffer
                reason = "no AX text; using liveBuffer as canonical fallback"
            } else {
                reason = "no source text available"
            }
        case .axValue, .axSelectedText, .axStringForRange:
            if liveBuffer.isEmpty {
                reason = "AX text available; no liveBuffer to reconcile"
            } else if rawText.hasSuffix(liveBuffer) {
                reason = "AX text already contains liveBuffer suffix"
            } else if rawText.isEmpty {
                canonicalText = liveBuffer
                didAppend = true
                reason = "AX text empty; liveBuffer becomes canonical cursor text"
            } else if liveBuffer.hasPrefix(rawText) {
                canonicalText = liveBuffer
                didAppend = true
                reason = "liveBuffer extends the complete AX text"
            } else {
                let lines = rawText.components(separatedBy: .newlines)
                let activeLine = lines.last ?? ""
                if !activeLine.isEmpty && liveBuffer.hasPrefix(activeLine) {
                    let previousLines = lines.dropLast().joined(separator: "\n")
                    canonicalText = previousLines.isEmpty ? liveBuffer : previousLines + "\n" + liveBuffer
                    didAppend = true
                    reason = "liveBuffer extends AX active line"
                } else {
                    reason = "AX text and liveBuffer do not have a provable suffix relationship; no append"
                }
            }
        }

        let context = CanonicalPredictionContext(
            canonicalTextBeforeCaret: canonicalText,
            liveBufferForPrompt: "",
            didAppendLiveBuffer: didAppend,
            appendReason: reason
        )

        print("""
        [Context Canonicalization Audit]
        AX source/method: \(snapshot.source.rawValue)
        raw textBeforeCaret: '\(contextAuditPreview(rawText))'
        raw liveBuffer: '\(contextAuditPreview(liveBuffer))'
        didAppendLiveBuffer: \(didAppend)
        append reason: \(reason)
        canonicalTextBeforeCaret: '\(contextAuditPreview(canonicalText))'
        activeLine sent to prompt: '\(contextAuditPreview(context.activeLine))'
        """)

        return context
    }

    private func syncFallbackBufferIfAuthoritative(_ context: CanonicalPredictionContext, source: TextBeforeCaretSource) {
        accessibilityMonitor?.synchronizeKeystrokeBuffer(
            withCanonicalText: context.canonicalTextBeforeCaret,
            source: source
        )
    }
    
    var isRewrite: Bool {
        return activeRewritePID != nil || activeRewriteText != nil
    }
    
    var isSmartReply: Bool {
        return activeSmartReplyPID != nil
    }

    private func beginResultRequest(activeLine: String) -> UInt64 {
        resultOwnershipLock.lock()
        latestResultRequestID &+= 1
        let requestID = latestResultRequestID
        resultOwnershipLock.unlock()

        print("[TypeFlow-Debug] Stage1A: result request #\(requestID) started for '\(activeLine.suffix(40))'")
        logStage1ACounters(context: "begin-request", generationResultRequestID: requestID, workID: workController.currentWorkID)
        return requestID
    }

    private func invalidateGenerationResults(reason: String, bufferSnapshot: String) {
        resultOwnershipLock.lock()
        latestResultRequestID &+= 1
        let requestID = latestResultRequestID
        resultOwnershipLock.unlock()

        print("[TypeFlow-Debug] Stage1A: result ownership advanced to #\(requestID) (\(reason)) for '\(bufferSnapshot.suffix(40))'")
        logStage1ACounters(context: "ownership-advanced-\(reason)", generationResultRequestID: requestID, workID: workController.currentWorkID)
    }

    private func isLatestResultRequest(_ requestID: UInt64) -> Bool {
        resultOwnershipLock.lock()
        defer { resultOwnershipLock.unlock() }
        return requestID == latestResultRequestID
    }

    private func isGenerationResultCurrent(requestID: UInt64, workID: UInt64) -> Bool {
        return workController.isCurrent(workID) && isLatestResultRequest(requestID)
    }

    private func shouldRenderGenerationResult(requestID: UInt64, workID: UInt64, source: String) -> Bool {
        guard isGenerationResultCurrent(requestID: requestID, workID: workID) else {
            logRenderDecision(allowed: false, requestID: requestID, workID: workID, source: source)
            recordStaleVisibleUpdateAttempt(requestID: requestID, workID: workID, source: source)
            return false
        }
        logRenderDecision(allowed: true, requestID: requestID, workID: workID, source: source)
        return true
    }

    private func shouldRenderOwnedResult(requestID: UInt64, workID: UInt64, source: String) -> Bool {
        guard isLatestResultRequest(requestID) else {
            logRenderDecision(allowed: false, requestID: requestID, workID: workID, source: source)
            recordStaleVisibleUpdateAttempt(requestID: requestID, workID: workID, source: source)
            return false
        }
        logRenderDecision(allowed: true, requestID: requestID, workID: workID, source: source)
        return true
    }

    private func makeResultOwnershipSnapshot(requestID: UInt64, workID: UInt64) -> ResultOwnershipSnapshot {
        let currentWorkID = workController.currentWorkID
        resultOwnershipLock.lock()
        let snapshot = ResultOwnershipSnapshot(
            latestResultRequestID: latestResultRequestID,
            generationResultRequestID: requestID,
            workID: workID,
            currentWorkID: currentWorkID,
            staleCompletedGenerationDiscardCount: staleCompletedGenerationDiscardCount,
            staleVisibleUpdateAttemptCount: staleVisibleUpdateAttemptCount
        )
        resultOwnershipLock.unlock()
        return snapshot
    }

    private func logRenderDecision(allowed: Bool, requestID: UInt64, workID: UInt64, source: String) {
        let snapshot = makeResultOwnershipSnapshot(requestID: requestID, workID: workID)
        print("[TypeFlow-Debug] Stage1A: render attempt \(allowed ? "ALLOWED" : "BLOCKED") from \(source) — latestResultRequestID=\(snapshot.latestResultRequestID), generationResultRequestID=\(snapshot.generationResultRequestID), workID=\(snapshot.workID), currentWorkID=\(snapshot.currentWorkID), staleCompletedDiscards=\(snapshot.staleCompletedGenerationDiscardCount), staleVisibleBlocks=\(snapshot.staleVisibleUpdateAttemptCount)")
    }

    private func logStage1ACounters(context: String, generationResultRequestID: UInt64, workID: UInt64) {
        let snapshot = makeResultOwnershipSnapshot(requestID: generationResultRequestID, workID: workID)
        print("[TypeFlow-Debug] Stage1A: counters after \(context) — latestResultRequestID=\(snapshot.latestResultRequestID), generationResultRequestID=\(snapshot.generationResultRequestID), workID=\(snapshot.workID), currentWorkID=\(snapshot.currentWorkID), staleCompletedDiscards=\(snapshot.staleCompletedGenerationDiscardCount), staleVisibleBlocks=\(snapshot.staleVisibleUpdateAttemptCount)")
    }

    private func recordStaleCompletedGenerationDiscard(requestID: UInt64, workID: UInt64) {
        resultOwnershipLock.lock()
        staleCompletedGenerationDiscardCount &+= 1
        let discardCount = staleCompletedGenerationDiscardCount
        let latestID = latestResultRequestID
        resultOwnershipLock.unlock()

        print("[TypeFlow-Debug] Stage1A: discarded completed stale generation request #\(requestID) (latest #\(latestID), workID \(workID)). Total stale completed discards: \(discardCount)")
        logStage1ACounters(context: "stale-completed-discard", generationResultRequestID: requestID, workID: workID)
    }

    private func recordStaleVisibleUpdateAttempt(requestID: UInt64, workID: UInt64, source: String) {
        resultOwnershipLock.lock()
        staleVisibleUpdateAttemptCount &+= 1
        let attemptCount = staleVisibleUpdateAttemptCount
        let latestID = latestResultRequestID
        resultOwnershipLock.unlock()

        print("[TypeFlow-Debug] Stage1A: blocked stale visible update from \(source) for request #\(requestID) (latest #\(latestID), workID \(workID)). Total blocked visible attempts: \(attemptCount)")
        logStage1ACounters(context: "stale-visible-block-\(source)", generationResultRequestID: requestID, workID: workID)
    }

    private func installGenerationCancellationToken(_ token: LlamaGenerationCancellationToken) {
        generationCancellationLock.lock()
        let previousToken = activeGenerationCancellationToken
        activeGenerationCancellationToken = token
        generationCancellationLock.unlock()

        if let previousToken, previousToken !== token, previousToken.requestCancellation() {
            print("[Stage1B] cancellation requested oldRequestID=\(previousToken.requestID) reason=new-generation")
        }
        print("[Stage1B] new generation started with fresh cancellation token requestID=\(token.requestID)")
    }

    private func clearGenerationCancellationTokenIfCurrent(_ token: LlamaGenerationCancellationToken) {
        generationCancellationLock.lock()
        if activeGenerationCancellationToken === token {
            activeGenerationCancellationToken = nil
        }
        generationCancellationLock.unlock()
    }

    private func requestActiveGenerationAbort(reason: String) {
        generationCancellationLock.lock()
        let token = activeGenerationCancellationToken
        generationCancellationLock.unlock()

        guard let token else { return }
        if token.requestCancellation() {
            print("[Stage1B] cancellation requested oldRequestID=\(token.requestID) reason=\(reason)")
        }
    }
    
    private init() {
        NotificationCenter.default.addObserver(
            forName: Notification.Name("TypeFlowModelLoadingStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            if let isLoading = notification.object as? Bool, !isLoading {
                if let pending = self.pendingCompletionRequest {
                    print("[TypeFlow-Debug] Model finished loading. Firing pending completion request: '\(pending)'")
                    self.pendingCompletionRequest = nil
                    self.triggerGeneration(with: pending)
                }
            }
        }
    }
    
    func setup(accessibilityMonitor: AccessibilityMonitor, overlayWindowController: OverlayWindowController) {
        self.accessibilityMonitor = accessibilityMonitor
        self.overlayWindowController = overlayWindowController
    }
    
    func getLastWord(from text: String) -> (word: String, range: NSRange)? {
        guard !text.isEmpty else { return nil }
        
        let chars = Array(text)
        var startIndex = chars.count
        
        var foundWordChar = false
        for i in (0..<chars.count).reversed() {
            let char = chars[i]
            let isWordChar = char.isLetter || char.isNumber || char == "'"
            if isWordChar {
                startIndex = i
                foundWordChar = true
            } else {
                break
            }
        }
        
        guard foundWordChar else { return nil }
        
        let word = String(chars[startIndex...])
        let startOffset = String(chars[..<startIndex]).utf16.count
        let length = word.utf16.count
        let range = NSRange(location: startOffset, length: length)
        
        return (word, range)
    }
    
    func getSpellCorrection(in text: String, lastWordRange: NSRange) -> String? {
        guard lastWordRange.length >= 4 else { return nil }
        
        let spellChecker = NSSpellChecker.shared
        let language = spellChecker.language()
        let word = (text as NSString).substring(with: lastWordRange)
        
        let startingAt = max(0, lastWordRange.location - 1)
        let misspelledRange = spellChecker.checkSpelling(
            of: text,
            startingAt: startingAt,
            language: language,
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: nil
        )
        
        let isMisspelled = (misspelledRange.location == lastWordRange.location && misspelledRange.length == lastWordRange.length)
        print("[TypeFlow-Debug] SpellCheck: Checking word '\(word)' (loc:\(lastWordRange.location) len:\(lastWordRange.length)) — misspelledRange: loc:\(misspelledRange.location) len:\(misspelledRange.length) — isMisspelled: \(isMisspelled)")
        guard isMisspelled else { return nil }
        
        if let corr = spellChecker.correction(forWordRange: lastWordRange, in: text, language: language, inSpellDocumentWithTag: 0), !corr.isEmpty {
            print("[TypeFlow-Debug] SpellCheck: correction() returned '\(corr)'")
            return corr
        }
        
        if let guesses = spellChecker.guesses(forWordRange: lastWordRange, in: text, language: language, inSpellDocumentWithTag: 0), !guesses.isEmpty {
            print("[TypeFlow-Debug] SpellCheck: guesses() returned \(guesses.prefix(5))")
            let wordLower = word.lowercased()
            let prefix2 = String(wordLower.prefix(2))
            if let bestMatch = guesses.first(where: { $0.lowercased().hasPrefix(prefix2) }) {
                return bestMatch
            }
            let prefix1 = String(wordLower.prefix(1))
            if let firstMatch = guesses.first(where: { $0.lowercased().hasPrefix(prefix1) }) {
                return firstMatch
            }
        }
        
        print("[TypeFlow-Debug] SpellCheck: No correction or guesses found for '\(word)'")
        return nil
    }
    
    func getGhostText(misspelled: String, correction: String) -> String {
        let misLower = misspelled.lowercased()
        let corrLower = correction.lowercased()
        if corrLower.hasPrefix(misLower) {
            return String(correction.dropFirst(misspelled.count))
        } else {
            return correction
        }
    }
    
    private func calculateDeleteCount(activeLine: String, misspelled: String) -> Int {
        if let range = activeLine.range(of: misspelled, options: [.backwards, .caseInsensitive]) {
            // Ensure bounds check when misspelled word is at index 0
            if range.lowerBound == activeLine.startIndex {
                return activeLine.utf16.distance(from: range.lowerBound, to: activeLine.endIndex)
            }
            return activeLine.utf16.distance(from: range.lowerBound, to: activeLine.endIndex)
        }
        return misspelled.count
    }
    
    private func getCompletedWord(from text: String) -> (word: String, delimiter: String, range: NSRange)? {
        guard !text.isEmpty else { return nil }
        
        let chars = Array(text)
        let lastChar = chars.last!
        
        let delimiters: Set<Character> = [" ", ".", ",", "!", "?"]
        guard delimiters.contains(lastChar) else { return nil }
        
        let delimiter = String(lastChar)
        
        var startIndex = chars.count - 1
        var foundWordChar = false
        
        for i in (0..<(chars.count - 1)).reversed() {
            let char = chars[i]
            let isWordChar = char.isLetter || char.isNumber || char == "'"
            if isWordChar {
                startIndex = i
                foundWordChar = true
            } else {
                break
            }
        }
        
        guard foundWordChar else { return nil }
        
        let word = String(chars[startIndex..<(chars.count - 1)])
        let startOffset = String(chars[..<startIndex]).utf16.count
        let length = word.utf16.count
        let range = NSRange(location: startOffset, length: length)
        
        return (word, delimiter, range)
    }
    
    func handleAsynchronousSpellcheck(bufferSnapshot: String) -> (misspelledLength: Int, correction: String)? {
        guard SettingsManager.shared.autoCorrectEnabled else { return nil }
        if let completedWordInfo = getCompletedWord(from: bufferSnapshot) {
            let word = completedWordInfo.word
            let wordRange = completedWordInfo.range
            let delimiter = completedWordInfo.delimiter
            
            if word.count >= 4, let correction = getSpellCorrection(in: bufferSnapshot, lastWordRange: wordRange) {
                print("[TypeFlow-Debug] Asynchronous auto-correct triggered: '\(word)' -> '\(correction)'")
                
                // Use the exact word length for deletion count instead of range distance to end of line
                let deleteCount = word.count
                
                DispatchQueue.main.async {
                    self.workController.cancelAll()
                    
                    // Buffer Alignment Protection for Screen UI: check if user typed anything while we were calculating
                    let currentBufferCount = self.accessibilityMonitor?.keystrokeBuffer.count ?? bufferSnapshot.count
                    let delta = currentBufferCount - bufferSnapshot.count
                    
                    guard delta >= 0 else {
                        print("[TypeFlow-Debug] SpellCheck UI: Aborting, user deleted text during async resolution.")
                        return
                    }
                    
                    // We must delete the word (deleteCount) PLUS the delimiter PLUS the newly typed chars
                    TextInjector.shared.injectBackspaces(count: deleteCount + delimiter.count + delta)
                    
                    // Re-inject the new characters after the correction
                    let newlyTyped = delta > 0 ? String(self.accessibilityMonitor?.keystrokeBuffer.suffix(delta) ?? "") : ""
                    
                    // Inject the correction and explicitly append the trailing space via pasteboard + newly typed
                    let trailingSpace = (delimiter == " ") ? " " : ""
                    TextInjector.shared.injectCharByChar(text: correction + delimiter + trailingSpace + newlyTyped)
                    
                    self.clearCompletion()
                }
                
                let correctedLine = String(bufferSnapshot.dropLast(deleteCount + delimiter.count)) + correction + delimiter
                print("[TypeFlow-Debug] Logging auto-corrected sentence to history: '\(correctedLine)'")
                TypingHistoryManager.shared.logSentenceFromText(correctedLine)
                return (word.count, correction + delimiter)
            }
        }
        return nil
    }
    
    func onTextChanged(bufferFallback: String = "") {
        if isRewrite || isSmartReply { return }
        // Suppressed: print("[TypeFlow-Debug] onTextChanged called")
        invalidateGenerationResults(reason: "text-changed", bufferSnapshot: bufferFallback)
        requestActiveGenerationAbort(reason: "new-input")
        
        if currentCompletion != nil && !currentCompletion!.isEmpty {
            print("[TypeFlow-Debug] onTextChanged: ignoring clear command because an active completion is present.")
            return
        }
        
        if workController.isGenerationRunning {
            print("[TypeFlow-Debug] onTextChanged: ignoring because a background generation is actively running.")
            return
        }
        
        if isSuppressedUntilNextTyping {
            let activeLine = bufferFallback.trimmingCharacters(in: .whitespacesAndNewlines)
            if !activeLine.isEmpty {
                print("[TypeFlow-Debug] Resetting submission suppression flag on new keystroke.")
                isSuppressedUntilNextTyping = false
            }
        }
        
        // ── Dynamic Typing Invalidation ──────────────────────────────────────
        // If an overlay is active, extract the newly typed character by diffing
        // against the previous buffer snapshot. If it matches the first char of
        // the ghost text, advance the suggestion instead of discarding it.
        if let ghost = currentCompletion, !ghost.isEmpty, !isRewrite, !isSmartReply {
            // Extract new characters appended since last snapshot
            let prev = lastBufferSnapshot
            let curr = bufferFallback
            if curr.count == prev.count + 1 && curr.hasPrefix(prev) {
                let newChar = String(curr.last!)
                let ghostFirst = String(ghost.prefix(1))
                if newChar == ghostFirst {
                    // Match — advance the canonical ghost text and redraw the remainder.
                    let advanced = String(ghost.dropFirst())
                    lastBufferSnapshot = curr
                    if advanced.isEmpty {
                        clearCompletion()
                    } else {
                        currentCompletion = advanced
                        overlayWindowController?.replaceGhostTextAfterAcceptance(inserted: newChar, remainder: advanced, source: "typedPrefix")
                        // Suppressed: print("[TypeFlow-Debug] DynamicInvalidation matched...")
                    }
                    return
                } else {
                    // Mismatch — mark as stale and cancel any pending debounce work,
                    // then fall through so a new completion is generated immediately.
                    // Suppressed: print("[TypeFlow-Debug] DynamicInvalidation mismatched...")
                    currentCompletion = nil
                    workController.cancelAll()
                    overlayWindowController?.updateGhostText(ghost, isStale: true)
                }
            } else {
                // Multi-char jump or deletion — mark as stale
                currentCompletion = nil
                workController.cancelAll()
                overlayWindowController?.updateGhostText(ghost, isStale: true)
            }
        }
        lastBufferSnapshot = bufferFallback
        
        // Clear existing completion state immediately when user types, but leave UI visible
        clearCompletion(hideUI: false)

        
        if let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
            if SettingsManager.shared.isAppExcluded(bundleId: bundleId) {
                clearCompletion()
                return
            }
        }
        
        // For the spacebar spellcheck, isolate the extraction strictly to the current word buffer.
        // We defer the heavy kAXValue polling to the debounce timer's background thread to prevent energy regression.
        let activeLine = bufferFallback
        
        TypingHistoryManager.shared.logSentenceFromText(activeLine)
        
        // 1. Check if the user just typed a completed word followed by a delimiter
        if let completedWordInfo = getCompletedWord(from: activeLine) {
            let word = completedWordInfo.word
            let wordRange = completedWordInfo.range
            let delimiter = completedWordInfo.delimiter
            
            if word.count >= 4, let correction = getSpellCorrection(in: activeLine, lastWordRange: wordRange) {
                print("[TypeFlow-Debug] Completed word spell correction found: '\(word)' -> '\(correction)'")
                
                // Cancel any pending LLM generation tasks
                workController.cancelAll()
                
                if SettingsManager.shared.autoCorrectEnabled {
                    print("[TypeFlow-Debug] Auto-correct is enabled. Automatically correcting '\(word)' to '\(correction)'")
                    let deleteCount = calculateDeleteCount(activeLine: activeLine, misspelled: word)
                    let correctedLine = String(activeLine.dropLast(deleteCount)) + correction + delimiter
                    print("[TypeFlow-Debug] Logging auto-corrected sentence to history: '\(correctedLine)'")
                    TypingHistoryManager.shared.logSentenceFromText(correctedLine)
                    
                    DispatchQueue.main.async {
                        TextInjector.shared.injectBackspaces(count: deleteCount)
                        let trailingSpace = (delimiter == " ") ? " " : ""
                        TextInjector.shared.injectCharByChar(text: correction + delimiter + trailingSpace)
                        self.clearCompletion()
                    }
                    return
                } else {
                    // Show it as orange ghost text suggestion
                    activeSpellCorrection = (misspelled: word, corrected: correction)
                    let ghostText = getGhostText(misspelled: word, correction: correction)
                    // Fetch caret rect lazily on the main thread just before showing the overlay —
                    // never during the hot typing loop.
                    DispatchQueue.main.async {
                        self.currentCompletion = ghostText
                        if !ghostText.isEmpty {
                            if let rect = self.accessibilityMonitor?.getCurrentCaretRect() {
                                self.overlayWindowController?.moveOverlay(to: rect)
                            }
                            self.overlayWindowController?.updateText(ghostText, isSpellCorrection: true)
                        } else {
                            self.overlayWindowController?.updateText("", isSpellCorrection: true)
                        }
                    }
                    return
                }
            }
        }
        
        // 2. If it's not a completed word with delimiter, check if it's an inline word being typed
        if let lastWordInfo = getLastWord(from: activeLine) {
            let word = lastWordInfo.word
            let wordRange = lastWordInfo.range
            
            // Only check inline if the word is at least 4 characters long
            if word.count >= 4 {
                // Check completions for partial word to see if it is a prefix of a valid word
                let completions = NSSpellChecker.shared.completions(
                    forPartialWordRange: NSRange(location: 0, length: word.utf16.count),
                    in: word,
                    language: NSSpellChecker.shared.language(),
                    inSpellDocumentWithTag: 0
                ) ?? []
                
                // If it is a prefix of a valid word (completions is not empty), we STOP using NSSpellChecker
                // and let it fall through to the LLM completion pipeline!
                if completions.isEmpty {
                    let correction = getSpellCorrection(in: activeLine, lastWordRange: wordRange)
                    print("[TypeFlow-Debug] SpellCheck: Checking word '\(word)' - result: \(correction ?? "nil")")
                    if let correction = correction {
                        print("[TypeFlow-Debug] Inline definite typo spell correction found: '\(word)' -> '\(correction)'")
                        // Cancel any pending LLM generation tasks
                        workController.cancelAll()
                        
                        activeSpellCorrection = (misspelled: word, corrected: correction)
                        
                        let ghostText = getGhostText(misspelled: word, correction: correction)
                        
                        // Always show orange ghost text for inline mid-word typos so the user
                        // has visual feedback — even when Auto-correct is enabled.
                        // (Silent auto-fix only fires on the delimiter-triggered path above.)
                        // Fetch caret rect lazily on the main thread just before showing the overlay —
                        // never during the hot typing loop.
                        DispatchQueue.main.async {
                            self.currentCompletion = ghostText
                            if !ghostText.isEmpty {
                                if let rect = self.accessibilityMonitor?.getCurrentCaretRect() {
                                    self.overlayWindowController?.moveOverlay(to: rect)
                                }
                                self.overlayWindowController?.updateText(ghostText, isSpellCorrection: true)
                            } else {
                                self.overlayWindowController?.updateText("", isSpellCorrection: true)
                            }
                        }
                        return
                    }
                }
            }
        }
        
        // Adaptive debounce: if typing rapidly (<150ms between keystrokes) use 150ms,
        // otherwise drop to 50ms so the first word gets a prediction nearly instantly.
        let now = Date()
        let keystrokeInterval = now.timeIntervalSince(lastKeystrokeTime)
        lastKeystrokeTime = now
        let debounceInterval: TimeInterval = keystrokeInterval < 0.15 ? 0.15 : 0.05
        // Suppressed: print("[TypeFlow-Debug] Adaptive debounce...")
        
        NotificationCenter.default.post(name: Notification.Name("UserDidType"), object: nil)
        
        workController.replaceDebouncedWork(delayMilliseconds: Int(debounceInterval * 1000)) { [weak self] _ in
            print("[TypeFlow-Debug] Debounce timer fired!")
            self?.triggerGeneration()
        }
    }
    
    private func triggerGeneration(with text: String? = nil) {
        guard SettingsManager.shared.enableAutocomplete else {
            print("[TypeFlow-Debug] triggerGeneration: Autocomplete disabled, skipping.")
            return
        }
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self else { return }
            
            if self.isSuppressedUntilNextTyping {
                print("[TypeFlow-Debug] triggerGeneration aborted due to isSuppressedUntilNextTyping.")
                return
            }
            
            print("[TypeFlow-Debug] triggerGeneration started. Cancelling any previous inflight task...")
            // workController manages the current work ID and will cancel its own tasks.
            
            if let providedText = text {
                logContextAudit("triggerGeneration source=providedText providedTextLen=\(providedText.count) providedText='\(contextAuditPreview(providedText))' liveBufferLen=0")
                let snapshot = PredictionSnapshot(rawTextBeforeCaret: providedText, source: .providedText, liveBuffer: "")
                self.continueGeneration(snapshot: snapshot)
            } else {
                // We MUST fetch AX text on a background thread because kAXValue polling is extremely expensive.
                let textSnapshot = self.accessibilityMonitor?.getTextBeforeCaretSnapshot()
                let axText = textSnapshot?.text ?? ""
                let axSource = textSnapshot?.source ?? .none
                let bufferAfterAX = self.accessibilityMonitor?.keystrokeBuffer ?? ""
                logContextAudit("triggerGeneration afterAX axSource=\(axSource.rawValue) axTextLen=\(axText.count) axText='\(contextAuditPreview(axText))' keystrokeBufferLen=\(bufferAfterAX.count) keystrokeBuffer='\(contextAuditPreview(bufferAfterAX))'")
                
                let isBrowser = ["zen", "safari", "chrome", "brave", "edge", "arc", "firefox"].contains {
                    NSWorkspace.shared.frontmostApplication?.localizedName?.lowercased().contains($0) == true ||
                    NSWorkspace.shared.frontmostApplication?.bundleIdentifier?.lowercased().contains($0) == true
                }
                
                if axText.count < 100 && isBrowser {
                    Task {
                        if let ocrText = await ScreenContextManager.shared.performRapidBrowserOCR() {
                            DispatchQueue.main.async {
                                // Append this OCR text to the === Screen Context === payload
                                ScreenContextManager.shared.latestScreenText = ocrText
                                let liveBuffer = self.accessibilityMonitor?.keystrokeBuffer ?? ""
                                let snapshot = PredictionSnapshot(
                                    rawTextBeforeCaret: !axText.isEmpty ? axText : liveBuffer,
                                    source: !axText.isEmpty ? axSource : .keystrokeBufferFallback,
                                    liveBuffer: liveBuffer
                                )
                                let finalLine = snapshot.rawTextBeforeCaret
                                self.logContextAudit("triggerGeneration dispatch viaBrowserOCR finalLineSource=\(snapshot.source.rawValue) axTextLen=\(axText.count) liveBufferLen=\(liveBuffer.count) finalLineLen=\(finalLine.count) finalLine='\(self.contextAuditPreview(finalLine))' liveBuffer='\(self.contextAuditPreview(liveBuffer))' ocrLen=\(ocrText.count)")
                                self.continueGeneration(snapshot: snapshot)
                            }
                        } else {
                            DispatchQueue.main.async {
                                let liveBuffer = self.accessibilityMonitor?.keystrokeBuffer ?? ""
                                let snapshot = PredictionSnapshot(
                                    rawTextBeforeCaret: !axText.isEmpty ? axText : liveBuffer,
                                    source: !axText.isEmpty ? axSource : .keystrokeBufferFallback,
                                    liveBuffer: liveBuffer
                                )
                                let finalLine = snapshot.rawTextBeforeCaret
                                self.logContextAudit("triggerGeneration dispatch viaBrowserNoOCR finalLineSource=\(snapshot.source.rawValue) axTextLen=\(axText.count) liveBufferLen=\(liveBuffer.count) finalLineLen=\(finalLine.count) finalLine='\(self.contextAuditPreview(finalLine))' liveBuffer='\(self.contextAuditPreview(liveBuffer))'")
                                self.continueGeneration(snapshot: snapshot)
                            }
                        }
                    }
                } else {
                    let liveBuffer = self.accessibilityMonitor?.keystrokeBuffer ?? ""
                    let snapshot = PredictionSnapshot(
                        rawTextBeforeCaret: !axText.isEmpty ? axText : liveBuffer,
                        source: !axText.isEmpty ? axSource : .keystrokeBufferFallback,
                        liveBuffer: liveBuffer
                    )
                    let finalLine = snapshot.rawTextBeforeCaret
                    
                    DispatchQueue.main.async {
                        self.logContextAudit("triggerGeneration dispatch direct finalLineSource=\(snapshot.source.rawValue) axTextLen=\(axText.count) liveBufferLen=\(liveBuffer.count) finalLineLen=\(finalLine.count) finalLine='\(self.contextAuditPreview(finalLine))' liveBuffer='\(self.contextAuditPreview(liveBuffer))'")
                        self.continueGeneration(snapshot: snapshot)
                    }
                }
            }
        }
    }
    
    private func continueGeneration(snapshot: PredictionSnapshot) {
        let canonicalContext = canonicalizePredictionSnapshot(snapshot)
        syncFallbackBufferIfAuthoritative(canonicalContext, source: snapshot.source)
        let activeLine = canonicalContext.canonicalTextBeforeCaret
        let keystrokeBuffer = snapshot.liveBuffer
        logContextAudit("continueGeneration input source=\(snapshot.source.rawValue) canonicalTextLen=\(activeLine.count) canonicalText='\(contextAuditPreview(activeLine))' rawTextLen=\(snapshot.rawTextBeforeCaret.count) liveBufferLen=\(keystrokeBuffer.count) liveBuffer='\(contextAuditPreview(keystrokeBuffer))'")
        guard !activeLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("[TypeFlow-Debug] Active line is empty, skipping generation.")
            return
        }
        
        let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        let effectiveConfig = SettingsManager.shared.getEffectiveConfig(for: bundleId)
        
        if !effectiveConfig.isEnabled {
            print("[TypeFlow-Debug] Completions disabled for \(bundleId), skipping.")
            return
        }
        
        // Snippets check
        let snippets = SettingsManager.shared.getSnippets()
        for (key, value) in snippets {
            if (key.hasPrefix("/") || key.hasPrefix(";")) && hasWordBoundaryBeforeSuffix(activeLine: activeLine, suffix: key) {
                print("[TypeFlow-Debug] Snippet matched: '\(key)' -> '\(value)'")
                activeSnippetKey = key
                
                let resolved = resolveSnippetPlaceholders(value)
                let (displayText, _) = processCursorPlaceholder(resolved)
                
                DispatchQueue.main.async {
                    self.currentCompletion = value
                    self.overlayWindowController?.updateText(displayText)
                }
                return
            }
        }
        activeSnippetKey = nil
        
        let fullActiveLine = canonicalContext.canonicalTextBeforeCaret
        let effectiveLiveBuffer = canonicalContext.liveBufferForPrompt
        logContextAudit("continueGeneration resolved source=\(snapshot.source.rawValue) didAppendLiveBuffer=\(canonicalContext.didAppendLiveBuffer) appendReason='\(canonicalContext.appendReason)' textBeforeCaretLen=\(fullActiveLine.count) textBeforeCaret='\(contextAuditPreview(fullActiveLine))' effectiveLiveBufferLen=\(effectiveLiveBuffer.count) effectiveLiveBuffer='\(contextAuditPreview(effectiveLiveBuffer))' originalRawTextLen=\(snapshot.rawTextBeforeCaret.count) originalLiveBufferLen=\(keystrokeBuffer.count)")
        
        self.generationStartCaretText = fullActiveLine
        let resultRequestID = beginResultRequest(activeLine: fullActiveLine)
        let generationStartText = fullActiveLine
        
        // Explicitly cancel any inflight task before creating a new one.
        let workID = workController.currentWorkID
        let generationCancellationToken = LlamaGenerationCancellationToken(requestID: resultRequestID, workID: workID)
        installGenerationCancellationToken(generationCancellationToken)
        print("[Stage1B] generation started requestID=\(resultRequestID) workID=\(workID)")
        
        workController.replaceGenerationWork(for: workID) { [weak self] in
            guard let self = self else { return }
            defer {
                self.clearGenerationCancellationTokenIfCurrent(generationCancellationToken)
                self.workController.setGenerationFinished()
            }
            
            // If this task was cancelled while waiting, abort early
            if Task.isCancelled || !self.workController.isCurrent(workID) { return }
            
            let modelReady = await LLMEngine.shared.isModelReady
            if !modelReady {
                print("[TypeFlow-Debug] Model is not ready yet. Queuing request: '\(fullActiveLine)'")
                await MainActor.run {
                    self.pendingCompletionRequest = activeLine
                }
                return
            }
            
            if Task.isCancelled { return }
            
            let completion = await LLMEngine.shared.generateCompletion(
                textBeforeCaret: fullActiveLine,
                liveBuffer: effectiveLiveBuffer,
                cancellationToken: generationCancellationToken,
                onStream: { [weak self] partialText in
                    guard let self = self else { return }
                    guard !generationCancellationToken.isCancelled else {
                        print("[Stage1B] stale/cancelled stream token suppressed requestID=\(resultRequestID)")
                        return
                    }
                    guard self.isGenerationResultCurrent(requestID: resultRequestID, workID: workID) else { return }
                    
                    let currentAX = self.accessibilityMonitor?.getTextBeforeCaret() ?? ""
                    let currentLine = !currentAX.isEmpty ? currentAX : (self.accessibilityMonitor?.keystrokeBuffer ?? "")
                    
                    let startText = generationStartText
                    var typedSinceStart = ""
                    if currentLine.hasPrefix(startText) {
                        typedSinceStart = String(currentLine.dropFirst(startText.count))
                    }
                    
                    var processed = SuggestionInteractionState.sliceGeneratedSuffix(activeLine: startText, rawCompletion: partialText)
                    processed = self.stripMarkdown(processed)
                    
                    if !processed.hasPrefix(typedSinceStart) && !typedSinceStart.hasPrefix(processed) {
                        print("[TypeFlow-Debug] Contradiction detected! processed: '\(processed)', typedSinceStart: '\(typedSinceStart)'. Cancelling task.")
                        guard self.shouldRenderGenerationResult(requestID: resultRequestID, workID: workID, source: "stream-contradiction") else { return }
                        self.workController.cancelAll()
                        DispatchQueue.main.async {
                            guard self.shouldRenderOwnedResult(requestID: resultRequestID, workID: workID, source: "stream-contradiction-main") else { return }
                            self.overlayWindowController?.updateText("")
                            self.onTextChanged(bufferFallback: currentLine)
                        }
                        return
                    }
                    
                    let remainder: String
                    if processed.hasPrefix(typedSinceStart) {
                        remainder = String(processed.dropFirst(typedSinceStart.count))
                    } else {
                        remainder = ""
                    }
                    
                    if remainder.contains("\n") {
                        if let newlineRange = remainder.range(of: "\n") {
                            let truncated = String(remainder[..<newlineRange.lowerBound])
                            guard self.shouldRenderGenerationResult(requestID: resultRequestID, workID: workID, source: "stream-newline") else { return }
                            self.workController.cancelAll()
                            DispatchQueue.main.async {
                                guard self.shouldRenderOwnedResult(requestID: resultRequestID, workID: workID, source: "stream-newline-main") else { return }
                                self.currentCompletion = truncated
                                if !truncated.isEmpty {
                                    if let rect = self.accessibilityMonitor?.getCurrentCaretRect() {
                                        self.overlayWindowController?.moveOverlay(to: rect)
                                    }
                                    self.overlayWindowController?.updateText(truncated)
                                } else {
                                    self.overlayWindowController?.updateText("")
                                }
                            }
                            return
                        }
                    }
                    
                    guard self.shouldRenderGenerationResult(requestID: resultRequestID, workID: workID, source: "stream") else { return }
                    
                    DispatchQueue.main.async {
                        guard self.shouldRenderGenerationResult(requestID: resultRequestID, workID: workID, source: "stream-main") else { return }
                        self.currentCompletion = remainder
                        if !remainder.isEmpty {
                            if let rect = self.accessibilityMonitor?.getCurrentCaretRect() {
                                self.overlayWindowController?.moveOverlay(to: rect)
                            }
                            self.overlayWindowController?.updateText(remainder)
                        } else {
                            self.overlayWindowController?.updateText("")
                        }
                    }
                }
            )
            if generationCancellationToken.isCancelled {
                print("[Stage1B] generation exited cancelled requestID=\(resultRequestID)")
                return
            }
            print("[TypeFlow-Debug] Raw model output: '\(completion.prefix(40))'")
            if Task.isCancelled || !self.isGenerationResultCurrent(requestID: resultRequestID, workID: workID) {
                if !self.isGenerationResultCurrent(requestID: resultRequestID, workID: workID) {
                    self.recordStaleCompletedGenerationDiscard(requestID: resultRequestID, workID: workID)
                }
                print("[TypeFlow-Debug] Task was cancelled or stale work ID, ignoring output.")
                return 
            }
            
            let currentAX = self.accessibilityMonitor?.getTextBeforeCaret() ?? ""
            let currentLine = !currentAX.isEmpty ? currentAX : (self.accessibilityMonitor?.keystrokeBuffer ?? "")
            
            let startText = generationStartText
            var typedSinceStart = ""
            if currentLine.hasPrefix(startText) {
                typedSinceStart = String(currentLine.dropFirst(startText.count))
            }
            
            var processedCompletion = SuggestionInteractionState.sliceGeneratedSuffix(activeLine: startText, rawCompletion: completion)
            processedCompletion = self.stripMarkdown(processedCompletion)
            
            if !processedCompletion.hasPrefix(typedSinceStart) && !typedSinceStart.hasPrefix(processedCompletion) {
                guard self.shouldRenderGenerationResult(requestID: resultRequestID, workID: workID, source: "final-contradiction") else { return }
                self.workController.cancelAll()
                DispatchQueue.main.async {
                    guard self.shouldRenderOwnedResult(requestID: resultRequestID, workID: workID, source: "final-contradiction-main") else { return }
                    self.overlayWindowController?.updateText("")
                    self.onTextChanged(bufferFallback: currentLine)
                }
                return
            }
            
            let remainder: String
            if processedCompletion.hasPrefix(typedSinceStart) {
                remainder = String(processedCompletion.dropFirst(typedSinceStart.count))
            } else {
                remainder = ""
            }
            
            var finalRemainder = remainder
            if finalRemainder.contains("\n") {
                if let newlineRange = finalRemainder.range(of: "\n") {
                    finalRemainder = String(finalRemainder[..<newlineRange.lowerBound])
                }
            }
            
            print("[TypeFlow-Debug] Processed completion: '\(finalRemainder.prefix(40))'")
            
            if Task.isCancelled || !self.shouldRenderGenerationResult(requestID: resultRequestID, workID: workID, source: "final") { return }
            
            DispatchQueue.main.async {
                guard self.shouldRenderGenerationResult(requestID: resultRequestID, workID: workID, source: "final-main") else { return }
                self.currentCompletion = finalRemainder
                if !finalRemainder.isEmpty {
                    UsageStatsManager.shared.recordCompletionShown()
                    if let rect = self.accessibilityMonitor?.getCurrentCaretRect() {
                        // Suppressed: print("[TypeFlow-Debug] Telling overlay to move to caret rect: \(rect)")
                        self.overlayWindowController?.moveOverlay(to: rect)
                    } else {
                        // Suppressed: print("[TypeFlow-Debug] Caret rect was nil, NOT moving overlay!")
                    }
                    // Suppressed: print("[TypeFlow-Debug] Telling overlay to update text to: '\(finalRemainder)'")
                    self.overlayWindowController?.updateText(finalRemainder)
                } else {
                    // Suppressed: print("[TypeFlow-Debug] Processed completion was empty, hiding overlay.")
                    self.overlayWindowController?.updateText("")
                }
            }
        }
    }
    
    /// Rewrite modes for the three popover buttons.
    enum RewriteMode {
        case selectMode        // wait for user to choose tone
        case currentTone       // uses the app's active tone profile
        case professional      // formal, polished
        case shorter           // cut to the point
        case fixGrammar        // grammar + spelling only, preserve meaning
    }

    func triggerRewrite(mode: RewriteMode = .selectMode) {
        print("[TypeFlow-Debug] CompletionManager: triggerRewrite called (mode: \(mode))")

        // Cancel previous tasks/timers immediately
        workController.cancelAll()
        rewriteTask?.cancel()
        activeSpellCorrection = nil
        activeSnippetKey = nil

        if mode == .selectMode {
            // Start of rewrite session: track original PID and clear previous text
            self.activeRewritePID = self.accessibilityMonitor?.activeFocusPID
            self.activeRewriteApp = NSWorkspace.shared.frontmostApplication
            self.activeRewriteText = nil
            self.currentCompletion = nil
            
            // Show the loading/mode selection overlay anchored to the selection
            DispatchQueue.main.async {
                if let rect = self.accessibilityMonitor?.getSelectionRect() {
                    self.overlayWindowController?.moveOverlay(to: rect)
                }
                self.overlayWindowController?.updateText("", isRewrite: true, isLoading: true)
            }

            // Asynchronously extract selection immediately while the target app is still frontmost
            self.rewriteTask?.cancel()
            self.rewriteTask = Task {
                try? await Task.sleep(nanoseconds: 100_000_000) // Settle delay
                
                guard let monitor = self.accessibilityMonitor,
                      let selection = await monitor.getSelectedTextWithClipboardFallback(),
                      !selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    print("[TypeFlow-Debug] triggerRewrite: No selection extracted, closing popover")
                    DispatchQueue.main.async { self.clearCompletion() }
                    return
                }
                
                print("[TypeFlow-Debug] triggerRewrite: Extracted selection '\(selection.prefix(30))...'")
                self.activeRewriteText = selection
            }
            return
        }

        // If a specific rewrite mode is selected:
        // 1. Immediately reactivate the target application to restore focus and selection
        if let pid = activeRewritePID, let app = NSRunningApplication(processIdentifier: pid) {
            if #available(macOS 14.0, *) {
                NSApplication.shared.yieldActivation(to: app)
                app.activate(options: [])
            } else {
                app.activate(options: [.activateIgnoringOtherApps])
            }
        }

        // 2. Update overlay to show "Generating..." spinner
        DispatchQueue.main.async {
            self.overlayWindowController?.updateText("Generating...", isRewrite: true, isLoading: true)
        }

        let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        
        if mode == .selectMode {
            return // unreachable
        }

        self.rewriteTask?.cancel()
        self.rewriteTask = Task { [weak self] in
            guard let self = self else { return }
            // Ensure selection is ready (wait up to 1 second if extraction is still running)
            var attempts = 0
            while self.activeRewriteText == nil && attempts < 10 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                attempts += 1
            }

            guard let selection = self.activeRewriteText,
                  !selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                print("[TypeFlow-Debug] triggerRewrite: Selection not available for rewrite")
                DispatchQueue.main.async { self.clearCompletion() }
                return
            }

            print("[TypeFlow-Debug] Rewriting selection")
            let rewritten = await LLMEngine.shared.generateRewrite(selectedText: selection)

            if Task.isCancelled {
                print("[TypeFlow-Debug] Rewrite generation cancelled")
                return
            }

            DispatchQueue.main.async {
                if !rewritten.isEmpty {
                    self.currentCompletion = rewritten
                    // Re-anchor overlay in case selection rect changed
                    if let rect = self.accessibilityMonitor?.getSelectionRect() {
                        self.overlayWindowController?.moveOverlay(to: rect)
                    }
                    self.overlayWindowController?.updateText(rewritten, isRewrite: true, isLoading: false)
                } else {
                    self.clearCompletion()
                }
            }
        }
    }

    func triggerSmartReply() {
        print("[TypeFlow-Debug] CompletionManager: triggerSmartReply called")
        
        workController.cancelAll()
        activeSpellCorrection = nil
        activeSnippetKey = nil
        
        self.activeSmartReplyPID = self.accessibilityMonitor?.activeFocusPID
        self.currentCompletion = nil
        
        DispatchQueue.main.async {
            if let rect = self.accessibilityMonitor?.getCurrentCaretRect() {
                self.overlayWindowController?.moveOverlay(to: rect)
            }
            self.overlayWindowController?.updateText("", isLoading: true, isSmartReply: true)
        }
        
        let workID = workController.currentWorkID
        workController.replaceGenerationWork(for: workID) { [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(nanoseconds: 100_000_000) // Settle delay
            
            let screenContext = ScreenContextManager.shared.latestScreenText
            let activeText = self.accessibilityMonitor?.getTextBeforeCaret() ?? ""
            
            let combinedContext = """
            On-Screen Text Context:
            \(screenContext)
            
            Currently Typed Text:
            \(activeText)
            """
            
            print("[TypeFlow-Debug] triggerSmartReply: context length = \(combinedContext.count)")
            
            let replies = await LLMEngine.shared.generateSmartReplies(contextText: combinedContext)
            
            if Task.isCancelled {
                print("[TypeFlow-Debug] triggerSmartReply cancelled")
                return
            }
            
            DispatchQueue.main.async {
                if !replies.isEmpty {
                    self.overlayWindowController?.updateText("", isSmartReply: true, smartReplyOptions: replies)
                } else {
                    self.clearCompletion()
                }
            }
        }
    }
    
    func acceptSmartReply(text: String) {
        print("[TypeFlow-Debug] Accepting smart reply: '\(text)'")
        
        let targetApp = activeSmartReplyPID.flatMap { NSRunningApplication(processIdentifier: $0) }
        let textToInject = text
        
        // 1. Hide UI + clear state on main thread immediately
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.overlayWindowController?.updateText("", isSpellCorrection: false, isRewrite: false, isLoading: false, isSmartReply: false, smartReplyOptions: [])
            self.accessibilityMonitor?.clearKeystrokeBuffer()
            self.clearCompletion()
        }
        
        // 2. Run pasteboard injection on a background thread so Thread.sleep
        //    doesn't block the main thread or prevent the UI from disappearing first.
        Task.detached(priority: .userInitiated) {
            TextInjector.shared.inject(text: textToInject, targetApp: targetApp)
        }
    }
    
    func handleTabPressed() -> Bool {
        if isRewrite {
            if let completion = currentCompletion, !completion.isEmpty {
                print("[TypeFlow-Debug] Accepting rewrite: replacing selection with '\(completion)'")
                
                let targetApp = activeRewriteApp
                
                // 1. Hide the overlay first so host app regains focus
                overlayWindowController?.updateText("", isSpellCorrection: false, isRewrite: false, isLoading: false, isSmartReply: false, smartReplyOptions: [])
                
                // 2. Clear keystroke buffer
                accessibilityMonitor?.clearKeystrokeBuffer()
                
                // 3. Forcibly reactivate target app
                targetApp?.activate(options: .activateIgnoringOtherApps)
                
                // 4. Delay and inject text asynchronously
                let completionToInject = completion
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    TextInjector.shared.inject(text: completionToInject, targetApp: targetApp)
                }
                
                // 5. Clear completion state
                clearCompletion()
            } else {
                print("[TypeFlow-Debug] Tab pressed during rewrite but completion not ready, ignoring.")
            }
            return true
        }
        
        if let spellCorrection = activeSpellCorrection {
            let activeLine = accessibilityMonitor?.getTextBeforeCaret() ?? ""
            let deleteCount = calculateDeleteCount(activeLine: activeLine, misspelled: spellCorrection.misspelled)
            print("[TypeFlow-Debug] Accept spell correction: activeLine='\(activeLine)', misspelled='\(spellCorrection.misspelled)', dynamically calculated deleteCount=\(deleteCount)")
            print("[TypeFlow-Debug] Accept spell correction: injecting \(deleteCount) backspaces and typing '\(spellCorrection.corrected)'")
            UsageStatsManager.shared.recordSpellCorrection()
            TextInjector.shared.injectBackspaces(count: deleteCount)
            TextInjector.shared.injectCharByChar(text: spellCorrection.corrected)
            clearCompletion()
            
            let correctedLine = String(activeLine.dropLast(deleteCount)) + spellCorrection.corrected
            print("[TypeFlow-Debug] Logging Tab-accepted spelling correction to history: '\(correctedLine)'")
            TypingHistoryManager.shared.logSentenceFromText(correctedLine)
            
            return true
        }
        
        if let snippetKey = activeSnippetKey, let rawCompletion = currentCompletion {
            let activeLine = accessibilityMonitor?.getTextBeforeCaret() ?? ""
            let resolved = resolveSnippetPlaceholders(rawCompletion)
            let (finalText, cursorOffset) = processCursorPlaceholder(resolved)
            
            TypingHistoryManager.shared.logSentence(activeLine + finalText)
            
            // Delete the shortcode
            let deleteCount = snippetKey.count
            UsageStatsManager.shared.recordSnippetFired()
            TextInjector.shared.injectBackspaces(count: deleteCount)
            
            // Inject replacement text and handle caret offset
            TextInjector.shared.inject(text: finalText, moveCursorBackCount: cursorOffset)
            
            clearCompletion()
            return true
        }
        
        if let completion = currentCompletion, !completion.isEmpty {
            let activeLine = accessibilityMonitor?.getTextBeforeCaret() ?? ""
            
            // ── Word-by-Word Tab Acceptance ────────────────────────────────────
            // Break at spaces, punctuation AND newlines. If the completion *starts*
            // with \n, accept only the newline so the user steps through line by line.
            let wordBreakChars: Set<Character> = [" ", ".", "_", "(", ")", ":", "/", ",", ";", "{", "}", "\n"]
            
            let wordToInsert: String
            let remainder: String
            
            if completion.hasPrefix("\n") {
                // Leading newline — accept just the newline, keep the rest
                wordToInsert = "\n"
                let after = String(completion.dropFirst())
                remainder = after
            } else {
                var breakIndex = completion.endIndex
                var foundBreak = false
                for (idx, ch) in completion.enumerated() {
                    if idx > 0 && wordBreakChars.contains(ch) {
                        breakIndex = completion.index(completion.startIndex, offsetBy: idx)
                        foundBreak = true
                        break
                    }
                }
                wordToInsert = String(completion[..<breakIndex])
                remainder = foundBreak ? String(completion[breakIndex...]) : ""
            }
            
            TypingHistoryManager.shared.logSentence(activeLine + completion)
            
            // Inject the first segment only.
            // CRITICAL: Use injectCharByChar (direct Unicode synthetic keystroke) NOT inject() here.
            UsageStatsManager.shared.recordCompletionAccepted(charactersSaved: completion.count)
            TextInjector.shared.injectCharByChar(text: wordToInsert)
            
            if !remainder.isEmpty {
                currentCompletion = remainder
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.overlayWindowController?.replaceGhostTextAfterAcceptance(inserted: wordToInsert, remainder: remainder, source: "tabAccept")
                }
                print("[TypeFlow-Debug] Word-by-word Tab: injected '\(wordToInsert)', remainder '\(remainder)' still shown")
            } else {
                print("[OverlayRender] tabAccept recomputeRemainderFromScratch inserted='\(wordToInsert)' remainder=''")
                print("[OverlayRender] hideBecauseEmptyRemainder")
                clearCompletion()
            }
            return true // We handled it
        }
        return false // Let the event pass through
    }
    
    func cancelInflightTasks() {
        requestActiveGenerationAbort(reason: "cancel-inflight")
        workController.cancelAll()
        rewriteTask?.cancel()
    }
    
    func hideOverlay() {
        overlayWindowController?.updateText("", isSpellCorrection: false, isRewrite: false, isLoading: false, isSmartReply: false, smartReplyOptions: [])
    }

    func clearCompletion(hideUI: Bool = true) {
        accessibilityMonitor?.setAcceptTapNeededForVisibleCompletion(false, reason: "clearCompletion")
        currentCompletion = nil
        activeSpellCorrection = nil
        activeSnippetKey = nil
        activeRewriteText = nil
        activeRewritePID = nil
        activeRewriteApp = nil
        activeSmartReplyPID = nil
        lastBufferSnapshot = ""
        cancelInflightTasks()
        if hideUI {
            hideOverlay()
        }
    }

    func handleReturnPressed() {
        // Wait slightly for the target app to process the Return key before polling AX API
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self = self else { return }
            let textAfterReturn = self.accessibilityMonitor?.getTextBeforeCaret()
            
            if textAfterReturn == nil || textAfterReturn!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print("[TypeFlow-Debug] Smart Submission Detected: Field is empty or lost focus after Return.")
                self.isSuppressedUntilNextTyping = true
                self.workController.cancelAll()
                self.overlayWindowController?.updateText("")
                self.clearCompletion()
            } else {
                print("[TypeFlow-Debug] Multi-line Newline Detected. Not suppressing.")
            }
        }
    }
    
    private func hasWordBoundaryBeforeSuffix(activeLine: String, suffix: String) -> Bool {
        guard activeLine.hasSuffix(suffix) else { return false }
        let prefixLength = activeLine.count - suffix.count
        guard prefixLength > 0 else { return true } // Start of line is a boundary
        
        let index = activeLine.index(activeLine.startIndex, offsetBy: prefixLength - 1)
        let charBefore = activeLine[index]
        return charBefore.isWhitespace || charBefore.isPunctuation
    }
    
    private func resolveSnippetPlaceholders(_ template: String) -> String {
        var result = template
        
        // 1. Resolve {{date}}
        if result.contains("{{date}}") {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let dateString = formatter.string(from: Date())
            result = result.replacingOccurrences(of: "{{date}}", with: dateString)
        }
        
        // 2. Resolve {{time}}
        if result.contains("{{time}}") {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            let timeString = formatter.string(from: Date())
            result = result.replacingOccurrences(of: "{{time}}", with: timeString)
        }
        
        // 3. Resolve {{clipboard}}
        if result.contains("{{clipboard}}") {
            let clipboardString = NSPasteboard.general.string(forType: .string) ?? ""
            result = result.replacingOccurrences(of: "{{clipboard}}", with: clipboardString)
        }
        
        return result
    }
    
    private func processCursorPlaceholder(_ text: String) -> (finalText: String, cursorOffset: Int) {
        guard let range = text.range(of: "{{cursor}}") else {
            return (text, 0)
        }
        
        let finalText = text.replacingOccurrences(of: "{{cursor}}", with: "")
        let substringAfterCursor = text[range.upperBound...]
        let cleanSubstring = substringAfterCursor.replacingOccurrences(of: "{{cursor}}", with: "")
        let cursorOffset = cleanSubstring.count
        
        return (finalText, cursorOffset)
    }
    
    func stripMarkdown(_ text: String) -> String {
        var result = text
        
        // Only strip trailing backticks the model might append
        if result.hasSuffix("```") {
            result = String(result.dropLast(3))
        } else if result.hasSuffix("``") {
            result = String(result.dropLast(2))
        } else if result.hasSuffix("`") {
            result = String(result.dropLast(1))
        }
        
        return result
    }
}

final class SuggestionWorkController: @unchecked Sendable {
    private var debounceTask: Task<Void, Never>?
    private var generationTask: Task<Void, Never>?
    private var isGenTaskActive = false
    private var latestWorkID: UInt64 = 0
    private let lock = NSLock()

    var currentWorkID: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return latestWorkID
    }

    var isGenerationRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isGenTaskActive
    }

    func setGenerationFinished() {
        lock.lock()
        isGenTaskActive = false
        lock.unlock()
    }

    @discardableResult
    func replaceDebouncedWork(
        delayMilliseconds: Int,
        operation: @escaping @Sendable (UInt64) async -> Void
    ) -> UInt64 {
        lock.lock()
        debounceTask?.cancel()
        // Do NOT cancel generationTask here to allow continuous background generation.
        latestWorkID &+= 1
        let workID = latestWorkID
        lock.unlock()

        let task = Task {
            let delayNanoseconds = UInt64(delayMilliseconds) * 1_000_000
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            if Task.isCancelled || !isCurrent(workID) { return }
            await operation(workID)
        }
        
        lock.lock()
        debounceTask = task
        lock.unlock()
        return workID
    }

    func replaceGenerationWork(
        for workID: UInt64,
        operation: @escaping @Sendable () async -> Void
    ) {
        lock.lock()
        generationTask?.cancel()
        isGenTaskActive = true
        let task = Task {
            defer {
                lock.lock()
                self.isGenTaskActive = false
                lock.unlock()
            }
            if Task.isCancelled || !isCurrent(workID) { return }
            await operation()
        }
        generationTask = task
        lock.unlock()
    }

    func cancelAll() {
        lock.lock()
        debounceTask?.cancel()
        generationTask?.cancel()
        debounceTask = nil
        generationTask = nil
        isGenTaskActive = false
        latestWorkID &+= 1
        lock.unlock()
    }

    func isCurrent(_ workID: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return workID == latestWorkID
    }
}

struct SuggestionInteractionState {
    static func sliceGeneratedSuffix(activeLine: String, rawCompletion: String) -> String {
        var processedCompletion = rawCompletion.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let maxOverlap = min(activeLine.count, processedCompletion.count)
        var overlapLength = 0
        
        if maxOverlap > 0 {
            for i in stride(from: maxOverlap, through: 1, by: -1) {
                let suffix = String(activeLine.suffix(i))
                let prefix = String(processedCompletion.prefix(i))
                if suffix == prefix {
                    overlapLength = i
                    break
                }
            }
        }
        
        if overlapLength > 0 {
            processedCompletion = String(processedCompletion.dropFirst(overlapLength))
        }
        
        return processedCompletion
    }
}
