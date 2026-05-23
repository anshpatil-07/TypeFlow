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
                keyDownEvent.post(tap: .cgSessionEventTap)
            }
            
            // Create KeyUp event
            if let keyUpEvent = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                keyUpEvent.keyboardSetUnicodeString(stringLength: 1, unicodeString: &varChar)
                keyUpEvent.post(tap: .cgSessionEventTap)
            }
        }
    }
}
