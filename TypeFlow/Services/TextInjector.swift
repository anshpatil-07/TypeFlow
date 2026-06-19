import Cocoa

class TextInjector {
    static let shared = TextInjector()
    var isInjecting = false
    
    private init() {}
    
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
        defer { isInjecting = false }
        
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
        
        // 3. Wait for TypeFlow UI to fully disappear and host window to settle
        Thread.sleep(forTimeInterval: 0.15)
        
        // 4. Post Cmd+V — use nil source so macOS assigns the current session state
        let vKeyCode: CGKeyCode = 9  // V key
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: true),
              let keyUp   = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: false) else {
            restoreClipboard(pasteboard: pasteboard, savedItems: savedItems)
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags   = .maskCommand
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
        
        // 5. Wait for the host to finish servicing Cmd+V, then restore original clipboard.
        // 50ms was too short — Chromium and other apps service paste asynchronously and can
        // take 100–200ms. Restoring before they service it causes them to paste the OLD clipboard
        // contents instead of our completion. 300ms matches Cotabby's pasteboardRestoreDelay.
        Thread.sleep(forTimeInterval: 0.3)
        restoreClipboard(pasteboard: pasteboard, savedItems: savedItems)
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
            if let keyDownEvent = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
                keyDownEvent.keyboardSetUnicodeString(stringLength: 1, unicodeString: &varChar)
                keyDownEvent.setIntegerValueField(.eventSourceUserData, value: 9999)
                keyDownEvent.flags = [] // Clear all modifiers
                keyDownEvent.post(tap: .cgSessionEventTap)
            }
            if let keyUpEvent = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                keyUpEvent.keyboardSetUnicodeString(stringLength: 1, unicodeString: &varChar)
                keyUpEvent.setIntegerValueField(.eventSourceUserData, value: 9999)
                keyUpEvent.flags = [] // Clear all modifiers
                keyUpEvent.post(tap: .cgSessionEventTap)
            }
            usleep(5000)
        }
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
                    keyDownEvent.post(tap: .cgSessionEventTap)
                }
                if let keyUpEvent = CGEvent(keyboardEventSource: source, virtualKey: 123, keyDown: false) {
                    keyUpEvent.setIntegerValueField(.eventSourceUserData, value: 9999)
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
                keyDownEvent.post(tap: .cgSessionEventTap)
            }
            if let keyUpEvent = CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: false) {
                keyUpEvent.setIntegerValueField(.eventSourceUserData, value: 9999)
                keyUpEvent.flags = [] // Clear all modifiers
                keyUpEvent.post(tap: .cgSessionEventTap)
            }
            usleep(5000)
        }
        
        if count > 0 {
            usleep(10000)
        }
    }
}
