import Cocoa

class TextInjector {
    static let shared = TextInjector()
    
    private init() {}
    
    func inject(text: String) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        
        // We will type out the characters using keyboardSetUnicodeString
        // To do this, we create a dummy keyDown and keyUp event, then set its unicode value
        let utf16Chars = Array(text.utf16)
        
        for char in utf16Chars {
            var varChar = char
            
            // Create KeyDown event
            if let keyDownEvent = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
                keyDownEvent.keyboardSetUnicodeString(stringLength: 1, unicodeString: &varChar)
                keyDownEvent.post(tap: .cghidEventTap)
            }
            
            // Create KeyUp event
            if let keyUpEvent = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                keyUpEvent.keyboardSetUnicodeString(stringLength: 1, unicodeString: &varChar)
                keyUpEvent.post(tap: .cghidEventTap)
            }
        }
    }
}
