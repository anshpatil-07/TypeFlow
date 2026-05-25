import Cocoa

struct AggregatedContext {
    let clipboardText: String?
    let screenText: String?
    let fullFieldText: String?
    let activeLineText: String
}

class ContextAggregator {
    static let shared = ContextAggregator()
    
    private init() {}
    
    func gatherContext(activeLine: String) -> AggregatedContext {
        // Clipboard and screen OCR are disabled: they inject noisy/irrelevant content
        // (e.g. Xcode logs in clipboard, IDE UI text via OCR) that confuses the model.
        // Only activeLineText (from the focused AX text field) is used until completions
        // are stable, at which point these can be re-enabled selectively.
        return AggregatedContext(
            clipboardText: nil,
            screenText: nil,
            fullFieldText: nil, // injected by CompletionManager from focused field
            activeLineText: activeLine
        )
    }
}
