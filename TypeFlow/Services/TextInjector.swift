import Cocoa

class TextInjector {
    static let shared = TextInjector()
    var isInjecting = false
    
    private init() {}
    
    func inject(text: String) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        
        isInjecting = true
        defer { isInjecting = false }
        
        let utf16Chars = Array(text.utf16)
        
        for char in utf16Chars {
            var varChar = char
            
            // Create KeyDown event
            if let keyDownEvent = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
                keyDownEvent.keyboardSetUnicodeString(stringLength: 1, unicodeString: &varChar)
                keyDownEvent.setIntegerValueField(.eventSourceUserData, value: 9999)
                keyDownEvent.post(tap: .cgSessionEventTap)
            }
            
            // Create KeyUp event
            if let keyUpEvent = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                keyUpEvent.keyboardSetUnicodeString(stringLength: 1, unicodeString: &varChar)
                keyUpEvent.setIntegerValueField(.eventSourceUserData, value: 9999)
                keyUpEvent.post(tap: .cgSessionEventTap)
            }
        }
    }
    
    func inject(text: String, moveCursorBackCount: Int) {
        inject(text: text)
        
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
    
    func injectBackspaces(count: Int) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        
        isInjecting = true
        defer { isInjecting = false }
        
        for _ in 0..<count {
            if let keyDownEvent = CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: true) {
                keyDownEvent.setIntegerValueField(.eventSourceUserData, value: 9999)
                keyDownEvent.post(tap: .cgSessionEventTap)
            }
            if let keyUpEvent = CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: false) {
                keyUpEvent.setIntegerValueField(.eventSourceUserData, value: 9999)
                keyUpEvent.post(tap: .cgSessionEventTap)
            }
        }
    }
}
