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

    func injectAcceptance(
        text: String,
        activeElement: AXUIElement?,
        startTime: CFAbsoluteTime,
        forceKeyboardFallback: Bool = false
    ) -> [String: Any] {
        markSyntheticEvent()
        let acceptStartedAt = startTime
        var insertionMethod = "characterFallback"
        var insertedAtomically = false
        var perCharacterFallback = true
        var acceptToFirstInsertedMs: Double = 0
        var acceptToFullInsertedMs: Double = 0
        var acceptSuccess = false
        var failReason = "none"
        
        let start = CFAbsoluteTimeGetCurrent()
        
        // Option 1: Accessibility API (Direct insertion)
        if !forceKeyboardFallback, let element = activeElement, verifyCaretCorrectness(element: element) {
            let status = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString)
            if status == .success {
                let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
                acceptToFirstInsertedMs = elapsed
                acceptToFullInsertedMs = elapsed
                insertionMethod = "accessibility"
                insertedAtomically = true
                perCharacterFallback = false
                acceptSuccess = true
            } else {
                print("[TypeFlow-Debug] Accessibility injection failed with status: \(status.rawValue)")
            }
        }
        
        // Option 2: Clipboard Pasteboard (Cmd+V)
        if !acceptSuccess {
            let start2 = CFAbsoluteTimeGetCurrent()
            let pasteboard = NSPasteboard.general
            
            // Save clipboard
            let savedItems = pasteboard.pasteboardItems?.compactMap { item -> NSPasteboardItem? in
                let newItem = NSPasteboardItem()
                for type in item.types {
                    if let data = item.data(forType: type) {
                        newItem.setData(data, forType: type)
                    }
                }
                return newItem
            }
            
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            
            // Post Cmd+V asynchronously after 50ms to let the Tab key event processing settle
            DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self = self else { return }
                let vKeyCode: CGKeyCode = 9
                if let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: true),
                   let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: false) {
                    
                    keyDown.flags = .maskCommand
                    keyUp.flags = .maskCommand
                    keyDown.setIntegerValueField(.eventSourceUserData, value: 9999)
                    keyUp.setIntegerValueField(.eventSourceUserData, value: 9999)
                    
                    self.isInjecting = true
                    self.logSyntheticKey(action: "cmd-v-posted-wordaccept", keyCode: vKeyCode, keyDown: true, text: "v", flags: keyDown.flags)
                    keyDown.post(tap: .cgSessionEventTap)
                    self.logSyntheticKey(action: "cmd-v-posted-wordaccept", keyCode: vKeyCode, keyDown: false, text: "v", flags: keyUp.flags)
                    keyUp.post(tap: .cgSessionEventTap)
                    self.isInjecting = false
                    
                    // Wait 80ms and restore
                    DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 0.08) {
                        self.restoreClipboard(pasteboard: pasteboard, savedItems: savedItems)
                    }
                } else {
                    self.restoreClipboard(pasteboard: pasteboard, savedItems: savedItems)
                }
            }
            
            let elapsed = (CFAbsoluteTimeGetCurrent() - start2) * 1000.0
            acceptToFirstInsertedMs = elapsed
            acceptToFullInsertedMs = elapsed
            insertionMethod = "clipboard"
            insertedAtomically = true
            perCharacterFallback = false
            acceptSuccess = true
        }
        
        // Option 4: Character-by-Character Fallback
        if !acceptSuccess {
            let start4 = CFAbsoluteTimeGetCurrent()
            guard let source = CGEventSource(stateID: .combinedSessionState) else {
                failReason = "no-event-source"
                return [
                    "acceptStartedAt": acceptStartedAt,
                    "insertionMethod": insertionMethod,
                    "acceptedText": text,
                    "acceptedTextLength": text.count,
                    "acceptToFirstInsertedMs": acceptToFirstInsertedMs,
                    "acceptToFullInsertedMs": acceptToFullInsertedMs,
                    "insertedAtomically": insertedAtomically,
                    "perCharacterFallback": perCharacterFallback,
                    "acceptSuccess": false,
                    "failReason": "no-event-source"
                ]
            }
            
            isInjecting = true
            let utf16Chars = Array(text.utf16)
            for (idx, char) in utf16Chars.enumerated() {
                var varChar = char
                let vKey: CGKeyCode = (char == 32) ? 49 : 0
                if let keyDownEvent = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true) {
                    if vKey == 0 {
                        keyDownEvent.keyboardSetUnicodeString(stringLength: 1, unicodeString: &varChar)
                    }
                    keyDownEvent.setIntegerValueField(.eventSourceUserData, value: 9999)
                    keyDownEvent.flags = []
                    keyDownEvent.post(tap: .cgSessionEventTap)
                }
                if let keyUpEvent = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) {
                    if vKey == 0 {
                        keyUpEvent.keyboardSetUnicodeString(stringLength: 1, unicodeString: &varChar)
                    }
                    keyUpEvent.setIntegerValueField(.eventSourceUserData, value: 9999)
                    keyUpEvent.flags = []
                    keyUpEvent.post(tap: .cgSessionEventTap)
                }
                
                if idx == 0 {
                    acceptToFirstInsertedMs = (CFAbsoluteTimeGetCurrent() - start4) * 1000.0
                }
                
                // Sleep briefly (5ms)
                usleep(5000)
            }
            isInjecting = false
            
            acceptToFullInsertedMs = (CFAbsoluteTimeGetCurrent() - start4) * 1000.0
            insertionMethod = "characterFallback"
            insertedAtomically = false
            perCharacterFallback = true
            acceptSuccess = true
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
            "acceptSuccess": acceptSuccess,
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
