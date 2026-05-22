import Cocoa

class ClipboardContextManager {
    static let shared = ClipboardContextManager()
    
    private init() {}
    
    func getClipboardText() -> String? {
        if let text = NSPasteboard.general.string(forType: .string) {
            // Truncate to 1000 characters to prevent prompt bloat
            if text.count > 1000 {
                return String(text.prefix(1000)) + "..."
            }
            return text
        }
        return nil
    }
}
