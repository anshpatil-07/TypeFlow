import Cocoa

class CompletionManager {
    static let shared = CompletionManager()
    
    var currentCompletion: String?
    weak var accessibilityMonitor: AccessibilityMonitor?
    weak var overlayWindowController: OverlayWindowController?
    
    private var debounceTimer: Timer?
    
    private init() {}
    
    func setup(accessibilityMonitor: AccessibilityMonitor, overlayWindowController: OverlayWindowController) {
        self.accessibilityMonitor = accessibilityMonitor
        self.overlayWindowController = overlayWindowController
    }
    
    func onTextChanged() {
        // Clear existing completion immediately when user types
        clearCompletion()
        
        // Debounce generation
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.triggerGeneration()
        }
    }
    
    private func triggerGeneration() {
        guard let context = accessibilityMonitor?.getTextBeforeCaret() else { return }
        
        Task {
            let completion = await LLMEngine.shared.generateCompletion(context: context)
            
            DispatchQueue.main.async {
                self.currentCompletion = completion
                // The overlay window will be updated with the caret position. We can update its text here.
                if let overlay = self.overlayWindowController?.overlayWindow?.contentView?.subviews.first as? NSTextField {
                    // Update text, but wait, the overlay uses SwiftUI currently!
                    // Let's implement an update method in OverlayWindowController
                }
                self.overlayWindowController?.updateText(completion)
            }
        }
    }
    
    func handleTabPressed() -> Bool {
        if let completion = currentCompletion, !completion.isEmpty {
            // Inject the text
            TextInjector.shared.inject(text: completion)
            clearCompletion()
            return true // We handled it
        }
        return false // Let the event pass through
    }
    
    func clearCompletion() {
        currentCompletion = nil
        overlayWindowController?.updateText("")
    }
}
