import Cocoa

class CompletionManager: @unchecked Sendable {
    static let shared = CompletionManager()
    
    var currentCompletion: String?
    weak var accessibilityMonitor: AccessibilityMonitor?
    weak var overlayWindowController: OverlayWindowController?
    
    private var debounceTimer: Timer?
    private var currentGenerationTask: Task<Void, Never>?
    
    private var pendingCompletionRequest: String?
    private var activeSpellCorrection: (misspelled: String, corrected: String)?
    private var activeSnippetKey: String?
    private var activeRewriteText: String?
    var activeRewritePID: pid_t?
    
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
    
    func onTextChanged(bufferFallback: String = "") {
        print("[TypeFlow-Debug] onTextChanged called")
        
        // Clear existing completion immediately when user types
        clearCompletion()
        
        if let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
            if SettingsManager.shared.isAppExcluded(bundleId: bundleId) {
                clearCompletion()
                return
            }
        }
        
        // Prefer AX-extracted text; fall back to the CGEvent buffer snapshot captured
        // at the tap site (before any racing focus-change dispatch could clear it).
        let axText = accessibilityMonitor?.getTextBeforeCaret() ?? ""
        let activeLine: String
        if !axText.isEmpty {
            activeLine = axText
        } else if !bufferFallback.isEmpty {
            print("[TypeFlow-Debug] AX returned empty — using CGEvent buffer snapshot for spell-check: '\(bufferFallback.suffix(50))'")
            activeLine = bufferFallback
        } else {
            activeLine = ""
        }
        
        TypingHistoryManager.shared.logSentenceFromText(activeLine)
        
        // 1. Check if the user just typed a completed word followed by a delimiter
        if let completedWordInfo = getCompletedWord(from: activeLine) {
            let word = completedWordInfo.word
            let wordRange = completedWordInfo.range
            let delimiter = completedWordInfo.delimiter
            
            if word.count >= 4, let correction = getSpellCorrection(in: activeLine, lastWordRange: wordRange) {
                print("[TypeFlow-Debug] Completed word spell correction found: '\(word)' -> '\(correction)'")
                
                // Cancel any pending LLM generation tasks
                debounceTimer?.invalidate()
                debounceTimer = nil
                currentGenerationTask?.cancel()
                currentGenerationTask = nil
                
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
                        debounceTimer?.invalidate()
                        debounceTimer = nil
                        currentGenerationTask?.cancel()
                        currentGenerationTask = nil
                        
                        activeSpellCorrection = (misspelled: word, corrected: correction)
                        
                        let ghostText = getGhostText(misspelled: word, correction: correction)
                        
                        // Always show orange ghost text for inline mid-word typos so the user
                        // has visual feedback — even when Auto-correct is enabled.
                        // (Silent auto-fix only fires on the delimiter-triggered path above.)
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
        
        // Debounce generation (strict 250ms debounce timer)
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
            print("[TypeFlow-Debug] Debounce timer fired!")
            self?.triggerGeneration()
        }
    }
    
    private func triggerGeneration(with text: String? = nil) {
        print("[TypeFlow-Debug] triggerGeneration started. Cancelling any previous inflight task...")
        currentGenerationTask?.cancel()
        currentGenerationTask = nil
        
        let activeLine = text ?? accessibilityMonitor?.getTextBeforeCaret() ?? ""
        guard !activeLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("[TypeFlow-Debug] Active line is empty, skipping generation.")
            return
        }
        
        if !LLMEngine.shared.isModelReady {
            print("[TypeFlow-Debug] Model is not ready yet. Queuing request: '\(activeLine)'")
            pendingCompletionRequest = activeLine
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
        
        print("[TypeFlow-Debug] Dispatching LLM generation for: '\(activeLine)'")
        
        currentGenerationTask = Task {
            let completion = await LLMEngine.shared.generateCompletion(
                textBeforeCaret: activeLine,
                toneProfile: effectiveConfig.toneProfile
            )
            print("[TypeFlow-Debug] Raw model output: '\(completion)'")
            if Task.isCancelled {
                print("[TypeFlow-Debug] Task was cancelled, ignoring output.")
                return 
            }
            
            var processedCompletion = completion.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Strip any echoed prefix overlap between the end of activeLine and start of completion
            let maxOverlap = min(activeLine.count, processedCompletion.count)
            var overlapLength = 0
            if maxOverlap > 0 {
                for i in (1...maxOverlap).reversed() {
                    let suffix = activeLine.suffix(i)
                    let prefix = processedCompletion.prefix(i)
                    if suffix.lowercased() == prefix.lowercased() {
                        overlapLength = i
                        break
                    }
                }
            }
            if overlapLength > 0 {
                processedCompletion = String(processedCompletion.dropFirst(overlapLength))
                processedCompletion = processedCompletion.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            // Strip markdown formatting
            processedCompletion = self.stripMarkdown(processedCompletion)
            
            print("[TypeFlow-Debug] Processed completion (after stripping \(overlapLength) chars overlap & markdown): '\(processedCompletion)'")
            
            if Task.isCancelled { return }
            
            DispatchQueue.main.async {
                self.currentCompletion = processedCompletion
                if !processedCompletion.isEmpty {
                    UsageStatsManager.shared.recordCompletionShown()
                    if let rect = self.accessibilityMonitor?.getCurrentCaretRect() {
                        print("[TypeFlow-Debug] Telling overlay to move to caret rect: \(rect)")
                        self.overlayWindowController?.moveOverlay(to: rect)
                    } else {
                        print("[TypeFlow-Debug] Caret rect was nil, NOT moving overlay!")
                    }
                    print("[TypeFlow-Debug] Telling overlay to update text to: '\(processedCompletion)'")
                    self.overlayWindowController?.updateText(processedCompletion)
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
        debounceTimer?.invalidate()
        debounceTimer = nil
        currentGenerationTask?.cancel()
        currentGenerationTask = nil
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
            currentGenerationTask = Task {
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

        currentGenerationTask = Task {
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

    
    func handleTabPressed() -> Bool {
        if let _ = activeRewriteText, let completion = currentCompletion, !completion.isEmpty {
            print("[TypeFlow-Debug] Accepting rewrite: replacing selection with '\(completion)'")
            TextInjector.shared.inject(text: completion)
            clearCompletion()
            return true
        }
        
        if let spellCorrection = activeSpellCorrection {
            let activeLine = accessibilityMonitor?.getTextBeforeCaret() ?? ""
            let deleteCount = calculateDeleteCount(activeLine: activeLine, misspelled: spellCorrection.misspelled)
            print("[TypeFlow-Debug] Accept spell correction: activeLine='\(activeLine)', misspelled='\(spellCorrection.misspelled)', dynamically calculated deleteCount=\(deleteCount)")
            print("[TypeFlow-Debug] Accept spell correction: injecting \(deleteCount) backspaces and typing '\(spellCorrection.corrected)'")
            UsageStatsManager.shared.recordSpellCorrection()
            TextInjector.shared.injectBackspaces(count: deleteCount)
            TextInjector.shared.inject(text: spellCorrection.corrected)
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
            TypingHistoryManager.shared.logSentence(activeLine + completion)
            
            // Inject the text
            UsageStatsManager.shared.recordCompletionAccepted(charactersSaved: completion.count)
            TextInjector.shared.inject(text: completion)
            clearCompletion()
            return true // We handled it
        }
        return false // Let the event pass through
    }
    
    func clearCompletion() {
        currentCompletion = nil
        activeSpellCorrection = nil
        activeSnippetKey = nil
        activeRewriteText = nil
        activeRewritePID = nil
        currentGenerationTask?.cancel()
        currentGenerationTask = nil
        overlayWindowController?.updateText("", isSpellCorrection: false, isRewrite: false, isLoading: false)
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
        // Remove bold/italic markup: **, *, __, _
        result = result.replacingOccurrences(of: "**", with: "")
        result = result.replacingOccurrences(of: "__", with: "")
        result = result.replacingOccurrences(of: "*", with: "")
        result = result.replacingOccurrences(of: "_", with: "")
        result = result.replacingOccurrences(of: "`", with: "")
        
        // Remove header markers like #, ##
        result = result.replacingOccurrences(of: "#", with: "")
        
        // Trim leading bullet symbols or markdown list symbols: e.g. "- ", "+ ", "* "
        let pattern = "^(\\s*[-+*]\\s+)+"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(location: 0, length: result.utf16.count)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
