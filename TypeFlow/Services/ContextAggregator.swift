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
        let clipboard = ClipboardContextManager.shared.getClipboardText()
        let screen = ScreenContextManager.shared.latestScreenText
        
        var fieldText: String?
        // Need to ask AccessibilityMonitor for full text but wait, we need to inject it.
        // It's better if CompletionManager passes it or we fetch it here.
        // Let's assume we call it here but we need a reference to the active monitor.
        // Since AccessibilityMonitor is mostly global, we can just instantiate a new one or use a shared instance if it was a singleton.
        // For now, let's just create an inline fetch or pass it in.
        
        return AggregatedContext(
            clipboardText: clipboard,
            screenText: screen.isEmpty ? nil : screen,
            fullFieldText: nil, // Will be injected by CompletionManager
            activeLineText: activeLine
        )
    }
}
