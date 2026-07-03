import Cocoa

class TextInjector {
    static let shared = TextInjector()
    var isInjecting = false
    private let auditLock = NSLock()
    private var lastSyntheticEventTime: CFAbsoluteTime = 0
    
    private init() {}

    func syntheticEventWithinLast(milliseconds: Double) -> Bool {
        auditLock.lock()
        let lastTime = lastSyntheticEventTime
        auditLock.unlock()
        guard lastTime > 0 else { return false }
        return (CFAbsoluteTimeGetCurrent() - lastTime) * 1000.0 <= milliseconds
    }

    func markSyntheticEvent() {
        auditLock.lock()
        lastSyntheticEventTime = CFAbsoluteTimeGetCurrent()
        auditLock.unlock()
    }

    private func logSyntheticKey(action: String, keyCode: CGKeyCode, keyDown: Bool, text: String = "", flags: CGEventFlags = []) {
        markSyntheticEvent()
        let escapedText = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "'", with: "\\'")
        let eventType = keyDown ? "keyDown" : "keyUp"
        let modifiers = String(flags.rawValue, radix: 16)
        let completionActive = CompletionManager.shared.displayedCompletion?.isEmpty == false
        let focusedPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        let overlayVisible = CompletionManager.shared.isOverlayVisible
        print("[TypeFlow-InputAudit] tap=synthetic eventType=\(eventType) keyCode=\(keyCode) chars='\(escapedText)' charsIgnoringModifiers='\(escapedText)' modifiers=0x\(modifiers) isARepeat=false timestamp=generated focusedPID=\(focusedPID) action=\(action) completionActive=\(completionActive) overlayVisible=\(overlayVisible) matchedShortcut=false modified=true swallowed=false reposted=true originalReturned=false syntheticEmitted=true")
    }
    
    // ── Pasteboard-based injection (bulletproof for smart reply / rewrite) ────
    // 1. Saves current clipboard
    // 2. Writes new text to clipboard
    // 3. Sleeps 150ms for TypeFlow UI to disappear + host app to settle
    // 4. Posts a single Cmd+V keystroke via cgSessionEventTap
    // 5. Sleeps 50ms, then restores original clipboard
    //
    // The `targetApp` parameter is accepted for API compatibility but no longer
    // used for activation — since TypeFlow is an LSUIElement running a
    // .nonactivatingPanel, the host app never truly loses focus, so
    // activation is unnecessary and only creates race conditions.
    func inject(text: String, targetApp: NSRunningApplication? = nil) {
        isInjecting = true
        
        let pasteboard = NSPasteboard.general
        
        // 1. Save existing clipboard contents
        let savedItems = pasteboard.pasteboardItems?.compactMap { item -> NSPasteboardItem? in
            let newItem = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    newItem.setData(data, forType: type)
                }
            }
            return newItem
        }
        
        // 2. Write new text to clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        // 3. Wrap the Cmd+V CGEvent simulation in a DispatchQueue.main.asyncAfter block
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let vKeyCode: CGKeyCode = 9  // V key
            guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: true),
                  let keyUp   = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: false) else {
                self.restoreClipboard(pasteboard: pasteboard, savedItems: savedItems)
                self.isInjecting = false
                return
            }
            
            keyDown.flags = .maskCommand
            keyUp.flags   = .maskCommand
            self.logSyntheticKey(action: "cmd-v-posted", keyCode: vKeyCode, keyDown: true, text: "v", flags: keyDown.flags)
            keyDown.post(tap: .cgSessionEventTap)
            self.logSyntheticKey(action: "cmd-v-posted", keyCode: vKeyCode, keyDown: false, text: "v", flags: keyUp.flags)
            keyUp.post(tap: .cgSessionEventTap)
            
            // 4. Inside that delayed block, add another asyncAfter before restoring
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.restoreClipboard(pasteboard: pasteboard, savedItems: savedItems)
                self.isInjecting = false
            }
        }
    }
    
    private func restoreClipboard(pasteboard: NSPasteboard, savedItems: [NSPasteboardItem]?) {
        pasteboard.clearContents()
        if let items = savedItems, !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }
    
    // ── Character-by-character injection (used for normal completions) ────────
    // Kept for snippets/spellcheck paths that need cursor-back movement.
    func injectCharByChar(text: String) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        
        isInjecting = true
        defer { isInjecting = false }
        
        let utf16Chars = Array(text.utf16)
        
        for char in utf16Chars {
            var varChar = char
            let vKey: CGKeyCode = (char == 32) ? 49 : 0
            if let keyDownEvent = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true) {
                if vKey == 0 {
                    keyDownEvent.keyboardSetUnicodeString(stringLength: 1, unicodeString: &varChar)
                }
                keyDownEvent.setIntegerValueField(.eventSourceUserData, value: 9999)
                keyDownEvent.flags = [] // Clear all modifiers
                logSyntheticKey(action: "unicode-char-posted", keyCode: vKey, keyDown: true, text: String(utf16CodeUnits: [char], count: 1), flags: keyDownEvent.flags)
                keyDownEvent.post(tap: .cgSessionEventTap)
            }
            if let keyUpEvent = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) {
                if vKey == 0 {
                    keyUpEvent.keyboardSetUnicodeString(stringLength: 1, unicodeString: &varChar)
                }
                keyUpEvent.setIntegerValueField(.eventSourceUserData, value: 9999)
                keyUpEvent.flags = [] // Clear all modifiers
                logSyntheticKey(action: "unicode-char-posted", keyCode: vKey, keyDown: false, text: String(utf16CodeUnits: [char], count: 1), flags: keyUpEvent.flags)
                keyUpEvent.post(tap: .cgSessionEventTap)
            }
            usleep(25000)
        }
    }

    // Returns true when the focused process is a browser whose contenteditable
    // uses AX bridges that do NOT safely support kAXSelectedTextAttribute writes.
    // Writing kAXSelectedTextAttribute in these processes replaces the entire
    // editable node content instead of inserting at the caret.
    static func isBrowserProcess(pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        // Check by frontmost app bundle identifier first (fast path)
        if let app = NSRunningApplication(processIdentifier: pid) {
            let bundle = app.bundleIdentifier ?? ""
            let browserBundles: Set<String> = [
                "com.apple.Safari",
                "com.google.Chrome",
                "com.google.Chrome.canary",
                "org.mozilla.firefox",
                "com.microsoft.edgemac",
                "com.brave.Browser",
                "company.thebrowser.Browser",  // Arc
                "com.zen.browser",               // Zen
                "io.zen.browser",
                "com.operasoftware.Opera",
                "com.vivaldi.Vivaldi",
            ]
            if browserBundles.contains(bundle) { return true }
            // Fallback: any app whose bundle prefix suggests a web engine
            let lowerBundle = bundle.lowercased()
            if lowerBundle.contains("webkit") || lowerBundle.contains("browser") || lowerBundle.contains("chrome") {
                return true
            }
        }
        return false
    }

    // Returns the PID of the focused element's owning process.
    private func focusedElementPID(element: AXUIElement) -> pid_t {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        return pid
    }

    // Injects text purely via Unicode CGEvent keystrokes, typing one char at a time.
    // This physically types at the caret and never touches existing text.
    private func injectCharByCharAtomic(text: String, startTime: CFAbsoluteTime) -> [String: Any] {
        let start = startTime
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            return [
                "insertionMethod": "charByChar",
                "insertedAtomically": false,
                "perCharacterFallback": true,
                "acceptToFirstInsertedMs": 0.0,
                "acceptToFullInsertedMs": 0.0,
                "insertionAPIReportedSuccess": false,
                "acceptSuccess": false,
                "failReason": "no-event-source"
            ]
        }
        isInjecting = true
        var acceptToFirstInsertedMs: Double = 0
        let utf16Chars = Array(text.utf16)
        for (idx, char) in utf16Chars.enumerated() {
            var varChar = char
            let vKey: CGKeyCode = (char == 32) ? 49 : 0
            if let keyDownEvent = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true) {
                if vKey == 0 { keyDownEvent.keyboardSetUnicodeString(stringLength: 1, unicodeString: &varChar) }
                keyDownEvent.setIntegerValueField(.eventSourceUserData, value: 9999)
                keyDownEvent.flags = []
                logSyntheticKey(action: "unicode-char-accept", keyCode: vKey, keyDown: true, text: String(utf16CodeUnits: [char], count: 1), flags: [])
                keyDownEvent.post(tap: .cgSessionEventTap)
            }
            if let keyUpEvent = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) {
                if vKey == 0 { keyUpEvent.keyboardSetUnicodeString(stringLength: 1, unicodeString: &varChar) }
                keyUpEvent.setIntegerValueField(.eventSourceUserData, value: 9999)
                keyUpEvent.flags = []
                keyUpEvent.post(tap: .cgSessionEventTap)
            }
            if idx == 0 { acceptToFirstInsertedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000.0 }
            usleep(5000)
        }
        isInjecting = false
        let acceptToFullInsertedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
        return [
            "insertionMethod": "charByChar",
            "insertedAtomically": false,
            "perCharacterFallback": true,
            "acceptToFirstInsertedMs": acceptToFirstInsertedMs,
            "acceptToFullInsertedMs": acceptToFullInsertedMs,
            "insertionAPIReportedSuccess": true,
            "acceptSuccess": true,
            "failReason": "none"
        ]
    }

    func injectAcceptance(
        text: String,
        activeElement: AXUIElement?,
        startTime: CFAbsoluteTime,
        forceKeyboardFallback: Bool = false
    ) -> [String: Any] {
        markSyntheticEvent()
        let acceptStartedAt = startTime
        var insertionMethod = "charByChar"
        var insertedAtomically = false
        var perCharacterFallback = true
        var acceptToFirstInsertedMs: Double = 0
        var acceptToFullInsertedMs: Double = 0
        var insertionAPIReportedSuccess = false
        var failReason = "none"

        let start = CFAbsoluteTimeGetCurrent()

        // Detect whether the focused process is a browser whose AX layer does NOT
        // safely support kAXSelectedTextAttribute writes. In these processes, writing
        // kAXSelectedTextAttribute replaces the entire contenteditable content even
        // when the selection length is 0 (zero-width caret).
        var isBrowser = false
        if let element = activeElement {
            let pid = focusedElementPID(element: element)
            isBrowser = TextInjector.isBrowserProcess(pid: pid)
        }
        print("[TypeFlow-Debug] injectAcceptance isBrowser=\(isBrowser) forceKeyboardFallback=\(forceKeyboardFallback) text='\(text)'")

        // --- Path 1: AX selected-text (ONLY for non-browser native AppKit fields) ---
        // NEVER use this path for browser/contenteditable.
        if !isBrowser && !forceKeyboardFallback,
           let element = activeElement,
           verifyCaretCorrectness(element: element) {
            let status = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString)
            insertionAPIReportedSuccess = (status == .success)
            if status == .success {
                let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
                acceptToFirstInsertedMs = elapsed
                acceptToFullInsertedMs = elapsed
                insertionMethod = "accessibility"
                insertedAtomically = true
                perCharacterFallback = false
                // NOTE: We do NOT set acceptSuccess=true here.
                // acceptSuccess is determined by the caller's transform verification.
                print("[TypeFlow-Debug] AX selected-text write returned success (not browser)")
            } else {
                print("[TypeFlow-Debug] AX selected-text write failed status=\(status.rawValue), falling through to charByChar")
            }
        } else if isBrowser {
            print("[TypeFlow-Debug] Browser detected — skipping AX selected-text, using charByChar injection")
        }

        // --- Path 2: Char-by-char Unicode CGEvent injection ---
        // Used for browsers and as fallback for native fields where AX write failed.
        // This path physically types characters at the current caret position without
        // touching any existing content — equivalent to the user typing the text.
        if insertionMethod != "accessibility" {
            let charResult = injectCharByCharAtomic(text: text, startTime: start)
            insertionMethod = charResult["insertionMethod"] as? String ?? "charByChar"
            insertedAtomically = charResult["insertedAtomically"] as? Bool ?? false
            perCharacterFallback = charResult["perCharacterFallback"] as? Bool ?? true
            acceptToFirstInsertedMs = charResult["acceptToFirstInsertedMs"] as? Double ?? 0
            acceptToFullInsertedMs = charResult["acceptToFullInsertedMs"] as? Double ?? 0
            insertionAPIReportedSuccess = charResult["insertionAPIReportedSuccess"] as? Bool ?? false
            failReason = charResult["failReason"] as? String ?? "none"
        }

        return [
            "acceptStartedAt": acceptStartedAt,
            "insertionMethod": insertionMethod,
            "acceptedText": text,
            "acceptedTextLength": text.count,
            "acceptToFirstInsertedMs": acceptToFirstInsertedMs,
            "acceptToFullInsertedMs": acceptToFullInsertedMs,
            "insertedAtomically": insertedAtomically,
            "perCharacterFallback": perCharacterFallback,
            // NOTE: acceptSuccess is intentionally NOT set here to true.
            // The caller (CompletionManager.handleTabPressed) must verify the
            // actual text transform before declaring success.
            "acceptSuccess": insertionAPIReportedSuccess,
            "insertionAPIReportedSuccess": insertionAPIReportedSuccess,
            "isBrowser": isBrowser,
            "failReason": failReason
        ]
    }

    private func verifyCaretCorrectness(element: AXUIElement) -> Bool {
        var rangeRef: AnyObject?
        let status = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef)
        guard status == .success, let axValue = rangeRef else {
            return false
        }
        var range = CFRange(location: 0, length: 0)
        let gotValue = AXValueGetValue(axValue as! AXValue, .cfRange, &range)
        return gotValue && range.length == 0
    }
    
    func inject(text: String, moveCursorBackCount: Int, targetApp: NSRunningApplication? = nil) {
        injectCharByChar(text: text)
        
        if moveCursorBackCount > 0 {
            guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
            
            isInjecting = true
            defer { isInjecting = false }
            
            for _ in 0..<moveCursorBackCount {
                if let keyDownEvent = CGEvent(keyboardEventSource: source, virtualKey: 123, keyDown: true) {
                    keyDownEvent.setIntegerValueField(.eventSourceUserData, value: 9999)
                    logSyntheticKey(action: "left-arrow-posted", keyCode: 123, keyDown: true, flags: keyDownEvent.flags)
                    keyDownEvent.post(tap: .cgSessionEventTap)
                }
                if let keyUpEvent = CGEvent(keyboardEventSource: source, virtualKey: 123, keyDown: false) {
                    keyUpEvent.setIntegerValueField(.eventSourceUserData, value: 9999)
                    logSyntheticKey(action: "left-arrow-posted", keyCode: 123, keyDown: false, flags: keyUpEvent.flags)
                    keyUpEvent.post(tap: .cgSessionEventTap)
                }
            }
        }
    }
    
    func injectBackspaces(count: Int, targetApp: NSRunningApplication? = nil) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        
        isInjecting = true
        defer { isInjecting = false }
        
        for _ in 0..<count {
            if let keyDownEvent = CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: true) {
                keyDownEvent.setIntegerValueField(.eventSourceUserData, value: 9999)
                keyDownEvent.flags = [] // Clear all modifiers
                logSyntheticKey(action: "backspace-posted", keyCode: 51, keyDown: true, flags: keyDownEvent.flags)
                keyDownEvent.post(tap: .cgSessionEventTap)
            }
            if let keyUpEvent = CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: false) {
                keyUpEvent.setIntegerValueField(.eventSourceUserData, value: 9999)
                keyUpEvent.flags = [] // Clear all modifiers
                logSyntheticKey(action: "backspace-posted", keyCode: 51, keyDown: false, flags: keyUpEvent.flags)
                keyUpEvent.post(tap: .cgSessionEventTap)
            }
            usleep(5000)
        }
        
        if count > 0 {
            usleep(10000)
        }
    }
}
