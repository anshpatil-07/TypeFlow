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
    var activeSmartReplyPID: pid_t?
    
    var isSuppressedUntilNextTyping = false
    private var lastBufferSnapshot: String = ""
    private var generationStartCaretText: String = ""
    
    var isRewrite: Bool {
        return activeRewritePID != nil || activeRewriteText != nil
    }
    
    var isSmartReply: Bool {
        return activeSmartReplyPID != nil
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
                    TextInjector.shared.inject(text: correction + delimiter + newlyTyped)
                    
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
        print("[TypeFlow-Debug] onTextChanged called")
        
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
                    // Match — advance the ghost text by one character using optimistic UI shift
                    let advanced = String(ghost.dropFirst())
                    lastBufferSnapshot = curr
                    if advanced.isEmpty {
                        clearCompletion()
                    } else {
                        currentCompletion = advanced
                        // Estimate single-char pixel width and slide the window right instantly
                        let font = NSFont.systemFont(ofSize: 13, weight: .regular)
                        let attrs = [NSAttributedString.Key.font: font]
                        let shiftPx = (newChar as NSString).size(withAttributes: attrs).width
                        overlayWindowController?.shiftOverlayX(by: shiftPx)
                        overlayWindowController?.updateGhostText(advanced)
                        print("[TypeFlow-Debug] DynamicInvalidation: char '\(newChar)' matched, shifted \(String(format: "%.1f", shiftPx))px, ghost advanced to '\(advanced)'")
                    }
                    return
                } else {
                    // Mismatch — instantly hide overlay and cancel any pending debounce work,
                    // then fall through so a new completion is generated immediately.
                    print("[TypeFlow-Debug] DynamicInvalidation: char '\(newChar)' mismatched ghost '\(ghostFirst)', clearing instantly")
                    currentCompletion = nil
                    workController.cancelAll()
                    overlayWindowController?.updateText("")
                }
            } else {
                // Multi-char jump or deletion — just clear
                currentCompletion = nil
                workController.cancelAll()
                overlayWindowController?.updateText("")
            }
        }
        lastBufferSnapshot = bufferFallback
        
        // Clear existing completion immediately when user types
        clearCompletion()

        
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
                    TextInjector.shared.injectBackspaces(count: deleteCount)
                    TextInjector.shared.inject(text: correction + delimiter)
                    clearCompletion()
                    
                    let correctedLine = String(activeLine.dropLast(deleteCount)) + correction + delimiter
                    print("[TypeFlow-Debug] Logging auto-corrected sentence to history: '\(correctedLine)'")
                    TypingHistoryManager.shared.logSentenceFromText(correctedLine)
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
        print("[TypeFlow-Debug] Adaptive debounce: keystroke interval \(String(format: "%.0f", keystrokeInterval * 1000))ms → using \(String(format: "%.0f", debounceInterval * 1000))ms")
        
        NotificationCenter.default.post(name: Notification.Name("UserDidType"), object: nil)
        
        workController.replaceDebouncedWork(delayMilliseconds: Int(debounceInterval * 1000)) { [weak self] _ in
            print("[TypeFlow-Debug] Debounce timer fired!")
            self?.triggerGeneration()
        }
    }
    
    private func triggerGeneration(with text: String? = nil) {
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self else { return }
            
            if self.isSuppressedUntilNextTyping {
                print("[TypeFlow-Debug] triggerGeneration aborted due to isSuppressedUntilNextTyping.")
                return
            }
            
            print("[TypeFlow-Debug] triggerGeneration started. Cancelling any previous inflight task...")
            // workController manages the current work ID and will cancel its own tasks.
            
            if let providedText = text {
                self.continueGeneration(activeLine: providedText, keystrokeBuffer: "")
            } else {
                // We MUST fetch AX text on a background thread because kAXValue polling is extremely expensive.
                let axText = self.accessibilityMonitor?.getTextBeforeCaret() ?? ""
                
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
                                let finalLine = !axText.isEmpty ? axText : self.accessibilityMonitor?.keystrokeBuffer ?? ""
                                let liveBuffer = self.accessibilityMonitor?.keystrokeBuffer ?? ""
                                self.continueGeneration(activeLine: finalLine, keystrokeBuffer: liveBuffer)
                            }
                        } else {
                            DispatchQueue.main.async {
                                let finalLine = !axText.isEmpty ? axText : self.accessibilityMonitor?.keystrokeBuffer ?? ""
                                let liveBuffer = self.accessibilityMonitor?.keystrokeBuffer ?? ""
                                self.continueGeneration(activeLine: finalLine, keystrokeBuffer: liveBuffer)
                            }
                        }
                    }
                } else {
                    let finalLine = !axText.isEmpty ? axText : self.accessibilityMonitor?.keystrokeBuffer ?? ""
                    let liveBuffer = self.accessibilityMonitor?.keystrokeBuffer ?? ""
                    
                    DispatchQueue.main.async {
                        self.continueGeneration(activeLine: finalLine, keystrokeBuffer: liveBuffer)
                    }
                }
            }
        }
    }
    
    private func continueGeneration(activeLine: String, keystrokeBuffer: String) {
        guard !activeLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("[TypeFlow-Debug] Active line is empty, skipping generation.")
            return
        }
        
        // --- Adaptive Pattern Engine Gate ---
        let adaptiveStopWordsEnabled = UserDefaults.standard.object(forKey: "adaptiveStopWordsEnabled") as? Bool ?? true
        if adaptiveStopWordsEnabled {
            let words = activeLine.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            if let lastWord = words.last?.lowercased(), AdaptivePatternLearner.shared.behaviors.stopWords.contains(lastWord) {
                print("[TypeFlow-Debug] Adaptive Engine: Active line ends with learned stop-word '\(lastWord)'. Skipping MLX.")
                return
            }
        }
        // ------------------------------------
        
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
        
        // ── Prompt Deduplication Guard ───────────────────────────────────────
        // When the Accessibility API successfully extracts text before the caret,
        // it is the definitive ground truth for the current field state. We must
        // NOT append the internal keystroke buffer to it: the AX text already
        // contains everything the user typed. The buffer is only used as a fallback
        // when AX extraction returns empty (e.g. sandboxed apps that block kAXValue).
        // Grafting the buffer onto the AX string was the root cause of the echoing
        // bug logged as: "Dispatching LLM generation for: 'the quick fox jumped the quick fox jumped'"
        let fullActiveLine: String
        let effectiveLiveBuffer: String
        if !activeLine.isEmpty {
            // AX text is available — use it exclusively, no buffer appended.
            fullActiveLine = activeLine
            effectiveLiveBuffer = ""
        } else {
            // AX unavailable — fall back to the keystroke buffer as both sources.
            fullActiveLine = keystrokeBuffer
            effectiveLiveBuffer = keystrokeBuffer
        }
        
        self.generationStartCaretText = fullActiveLine
        
        // Explicitly cancel any inflight task before creating a new one.
        let workID = workController.currentWorkID
        
        workController.replaceGenerationWork(for: workID) { [weak self] in
            guard let self = self else { return }
            defer {
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
                toneProfile: effectiveConfig.toneProfile,
                onStream: { [weak self] partialText in
                    guard let self = self else { return }
                    guard self.workController.isCurrent(workID) else { return }
                    
                    let currentAX = self.accessibilityMonitor?.getTextBeforeCaret() ?? ""
                    let currentLine = !currentAX.isEmpty ? currentAX : (self.accessibilityMonitor?.keystrokeBuffer ?? "")
                    
                    let startText = self.generationStartCaretText
                    var typedSinceStart = ""
                    if currentLine.hasPrefix(startText) {
                        typedSinceStart = String(currentLine.dropFirst(startText.count))
                    }
                    
                    var processed = SuggestionInteractionState.sliceGeneratedSuffix(activeLine: startText, rawCompletion: partialText)
                    processed = self.stripMarkdown(processed)
                    
                    if !processed.hasPrefix(typedSinceStart) && !typedSinceStart.hasPrefix(processed) {
                        print("[TypeFlow-Debug] Contradiction detected! processed: '\(processed)', typedSinceStart: '\(typedSinceStart)'. Cancelling task.")
                        self.workController.cancelAll()
                        DispatchQueue.main.async {
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
                            self.workController.cancelAll()
                            DispatchQueue.main.async {
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
                    
                    guard self.workController.isCurrent(workID) else { return }
                    
                    DispatchQueue.main.async {
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
            print("[TypeFlow-Debug] Raw model output: '\(completion)'")
            if Task.isCancelled || !self.workController.isCurrent(workID) {
                print("[TypeFlow-Debug] Task was cancelled or stale work ID, ignoring output.")
                return 
            }
            
            let currentAX = self.accessibilityMonitor?.getTextBeforeCaret() ?? ""
            let currentLine = !currentAX.isEmpty ? currentAX : (self.accessibilityMonitor?.keystrokeBuffer ?? "")
            
            let startText = self.generationStartCaretText
            var typedSinceStart = ""
            if currentLine.hasPrefix(startText) {
                typedSinceStart = String(currentLine.dropFirst(startText.count))
            }
            
            var processedCompletion = SuggestionInteractionState.sliceGeneratedSuffix(activeLine: startText, rawCompletion: completion)
            processedCompletion = self.stripMarkdown(processedCompletion)
            
            if !processedCompletion.hasPrefix(typedSinceStart) && !typedSinceStart.hasPrefix(processedCompletion) {
                self.workController.cancelAll()
                DispatchQueue.main.async {
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
            
            print("[TypeFlow-Debug] Processed completion (after stripping overlap & markdown): '\(finalRemainder)'")
            
            if Task.isCancelled || !self.workController.isCurrent(workID) { return }
            
            DispatchQueue.main.async {
                self.currentCompletion = finalRemainder
                if !finalRemainder.isEmpty {
                    UsageStatsManager.shared.recordCompletionShown()
                    if let rect = self.accessibilityMonitor?.getCurrentCaretRect() {
                        print("[TypeFlow-Debug] Telling overlay to move to caret rect: \(rect)")
                        self.overlayWindowController?.moveOverlay(to: rect)
                    } else {
                        print("[TypeFlow-Debug] Caret rect was nil, NOT moving overlay!")
                    }
                    print("[TypeFlow-Debug] Telling overlay to update text to: '\(finalRemainder)'")
                    self.overlayWindowController?.updateText(finalRemainder)
                } else {
                    print("[TypeFlow-Debug] Processed completion was empty, hiding overlay.")
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
        activeSpellCorrection = nil
        activeSnippetKey = nil

        if mode == .selectMode {
            // Start of rewrite session: track original PID and clear previous text
            self.activeRewritePID = self.accessibilityMonitor?.activeFocusPID
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
            let workID = workController.currentWorkID
            workController.replaceGenerationWork(for: workID) {
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
        let effectiveConfig = SettingsManager.shared.getEffectiveConfig(for: bundleId)
        let toneProfile: ToneProfile
        switch mode {
        case .selectMode:
            return // unreachable
        case .currentTone:
            toneProfile = effectiveConfig.toneProfile
        case .professional:
            toneProfile = ToneProfile(
                id: "rewrite-professional", name: "Professional",
                systemInstructions: "Rewrite the text in a clear, professional, and formal tone. Preserve the original meaning exactly. Output ONLY the rewritten text with no commentary.",
                temperature: 0.1, maxTokens: 300, isBuiltIn: true)
        case .shorter:
            toneProfile = ToneProfile(
                id: "rewrite-shorter", name: "Shorter",
                systemInstructions: "Rewrite the text to be significantly shorter and more concise without losing the core meaning. Cut unnecessary words and phrases. Output ONLY the rewritten text.",
                temperature: 0.1, maxTokens: 200, isBuiltIn: true)
        case .fixGrammar:
            toneProfile = ToneProfile(
                id: "rewrite-grammar", name: "Fix Grammar",
                systemInstructions: "Fix all spelling mistakes, grammar errors, and punctuation in the text. Do NOT change the meaning, style, or vocabulary beyond necessary corrections. Output ONLY the corrected text.",
                temperature: 0.0, maxTokens: 300, isBuiltIn: true)
        }

        let workID = workController.currentWorkID
        workController.replaceGenerationWork(for: workID) { [weak self] in
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

            print("[TypeFlow-Debug] Rewriting selection with mode '\(toneProfile.name)'")
            let rewritten = await LLMEngine.shared.generateRewrite(selectedText: selection, toneProfile: toneProfile)

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
                
                let targetApp = activeRewritePID.flatMap { NSRunningApplication(processIdentifier: $0) }
                
                // 1. Hide the overlay first so host app regains focus
                overlayWindowController?.updateText("", isSpellCorrection: false, isRewrite: false, isLoading: false, isSmartReply: false, smartReplyOptions: [])
                
                // 2. Clear keystroke buffer
                accessibilityMonitor?.clearKeystrokeBuffer()
                
                // 3. Introduce a delay and inject text asynchronously
                let completionToInject = completion
                Task {
                    try? await Task.sleep(nanoseconds: 50_000_000) // 50ms delay
                    TextInjector.shared.inject(text: completionToInject, targetApp: targetApp)
                }
                
                // 4. Clear completion state
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
                // Optimistic UI: instantly advance the overlay X by the pixel width of the
                // accepted word so it tracks the caret without waiting for an AX round-trip.
                let font = NSFont.systemFont(ofSize: 13, weight: .regular)
                let attrs = [NSAttributedString.Key.font: font]
                let shiftPx = (wordToInsert as NSString).size(withAttributes: attrs).width
                currentCompletion = remainder
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.overlayWindowController?.shiftOverlayX(by: shiftPx)
                    self.overlayWindowController?.updateGhostText(remainder)
                }
                print("[TypeFlow-Debug] Word-by-word Tab: injected '\(wordToInsert)', shifted \(String(format: "%.1f", shiftPx))px, remainder '\(remainder)' still shown")
            } else {
                clearCompletion()
            }
            return true // We handled it
        }
        return false // Let the event pass through
    }
    
    func cancelInflightTasks() {
        workController.cancelAll()
    }
    
    func hideOverlay() {
        overlayWindowController?.updateText("", isSpellCorrection: false, isRewrite: false, isLoading: false, isSmartReply: false, smartReplyOptions: [])
    }

    func clearCompletion() {
        currentCompletion = nil
        activeSpellCorrection = nil
        activeSnippetKey = nil
        activeRewriteText = nil
        activeRewritePID = nil
        activeSmartReplyPID = nil
        lastBufferSnapshot = ""
        cancelInflightTasks()
        hideOverlay()
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
