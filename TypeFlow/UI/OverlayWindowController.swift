import Cocoa
import SwiftUI

class CompletionModel: ObservableObject {
    @Published var text: String = ""
}

struct CompletionOverlayView: View {
    @ObservedObject var model: CompletionModel
    
    var body: some View {
        if model.text.isEmpty {
            Color.clear
        } else {
            Text(model.text)
                .foregroundColor(Color.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(NSColor.windowBackgroundColor).opacity(0.9))
                )
                .font(.system(size: 13, weight: .regular))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

class OverlayWindowController: NSWindowController {
    var overlayWindow: NSWindow!
    private let completionModel = CompletionModel()
    private var lastCaretRect = CGRect.zero
    
    init() {
        let hostingView = NSHostingView(rootView: CompletionOverlayView(model: completionModel))
        
        overlayWindow = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 200, height: 24),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        overlayWindow.level = .floating
        overlayWindow.backgroundColor = .clear
        overlayWindow.ignoresMouseEvents = true
        overlayWindow.isOpaque = false
        overlayWindow.contentView = hostingView
        overlayWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        super.init(window: overlayWindow)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func moveOverlay(to rect: CGRect) {
        lastCaretRect = rect
        repositionWindow()
    }
    
    private func repositionWindow() {
        guard !completionModel.text.isEmpty else { return }
        
        let font = NSFont.systemFont(ofSize: 13, weight: .regular)
        let attributes = [NSAttributedString.Key.font: font]
        let size = (completionModel.text as NSString).size(withAttributes: attributes)
        let textWidth = size.width + 12 // text width + horizontal padding
        
        // macOS screen coordinates: (0,0) is bottom-left, but AX returns coordinates from top-left.
        // We need to flip the y coordinate based on the main display bounds.
        let displayHeight = CGDisplayBounds(CGMainDisplayID()).height
        let flippedY = displayHeight - lastCaretRect.origin.y - lastCaretRect.height
        
        // Move it slightly to the right of the caret (approx 2 pixels) and size it exactly to fit the text
        let newFrame = CGRect(
            x: lastCaretRect.origin.x + lastCaretRect.width + 2,
            y: flippedY,
            width: textWidth,
            height: 24
        )
        overlayWindow.setFrame(newFrame, display: true)
    }
    
    func updateText(_ newText: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.completionModel.text = newText
            if newText.isEmpty {
                self.overlayWindow.orderOut(nil)
            } else {
                self.repositionWindow()
                self.overlayWindow.orderFront(nil)
            }
        }
    }
}
