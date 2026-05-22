import Cocoa
import SwiftUI

class OverlayWindowController: NSWindowController {
    var overlayWindow: NSWindow!
    private var hostingView: NSHostingView<Text>?
    
    init() {
        let text = Text(" ghost completion")
            .foregroundColor(Color(NSColor.secondaryLabelColor))
            .font(.system(size: 13, weight: .regular))
        hostingView = NSHostingView(rootView: text)
        
        overlayWindow = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 200, height: 20),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        overlayWindow.level = .floating
        overlayWindow.backgroundColor = .clear
        overlayWindow.ignoresMouseEvents = true
        overlayWindow.isOpaque = false
        overlayWindow.contentView = hostingView
        
        super.init(window: overlayWindow)
        overlayWindow.makeKeyAndOrderFront(nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func moveOverlay(to rect: CGRect) {
        // macOS screen coordinates: (0,0) is bottom-left, but AX returns coordinates from top-left.
        // We need to flip the y coordinate.
        if let screen = NSScreen.main {
            let flippedY = screen.frame.height - rect.origin.y - rect.height
            // Move it slightly to the right of the caret
            let newFrame = CGRect(x: rect.origin.x + rect.width, y: flippedY, width: 200, height: 20)
            overlayWindow.setFrame(newFrame, display: true)
        }
    }
    
    func updateText(_ newText: String) {
        let text = Text(newText)
            .foregroundColor(Color(NSColor.secondaryLabelColor))
            .font(.system(size: 13, weight: .regular))
        hostingView?.rootView = text
    }
}
