import Cocoa
import SwiftUI

class CompletionModel: ObservableObject {
    @Published var text: String = ""
    @Published var isSpellCorrection: Bool = false
    @Published var isRewrite: Bool = false
    @Published var isLoading: Bool = false
}

struct CompletionOverlayView: View {
    @ObservedObject var model: CompletionModel
    
    var body: some View {
        if model.text.isEmpty && !model.isLoading {
            Color.clear
        } else {
            HStack(spacing: 6) {
                if model.isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                } else if model.isRewrite {
                    Text("REWRITE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            LinearGradient(
                                colors: [Color.teal, Color.blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .cornerRadius(3)
                }
                
                Text(model.isLoading ? "Rewriting selection..." : model.text)
                    .foregroundColor(model.isRewrite ? Color.primary : (model.isSpellCorrection ? Color.orange : Color.secondary))
            }
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
        guard !completionModel.text.isEmpty || completionModel.isLoading else { return }
        
        let font = NSFont.systemFont(ofSize: 13, weight: .regular)
        let attributes = [NSAttributedString.Key.font: font]
        let measureText = completionModel.isLoading ? "Rewriting selection..." : completionModel.text
        let size = (measureText as NSString).size(withAttributes: attributes)
        var textWidth = size.width + 12 // text width + horizontal padding
        
        if completionModel.isRewrite && !completionModel.isLoading {
            textWidth += 65 // Extra padding for rewrite pill badge
        }
        
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
        print("[TypeFlow-Debug] OverlayWindowController rendering window at frame: \(newFrame) with text: '\(completionModel.text)'")
        overlayWindow.setFrame(newFrame, display: true)
    }
    
    func updateText(_ newText: String, isSpellCorrection: Bool = false, isRewrite: Bool = false, isLoading: Bool = false) {
        print("[TypeFlow-Debug] OverlayWindowController updateText received: '\(newText)', isSpellCorrection: \(isSpellCorrection), isRewrite: \(isRewrite), isLoading: \(isLoading)")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.completionModel.isSpellCorrection = isSpellCorrection
            self.completionModel.isRewrite = isRewrite
            self.completionModel.isLoading = isLoading
            self.completionModel.text = newText
            if newText.isEmpty && !isLoading {
                print("[TypeFlow-Debug] Hiding overlay window")
                self.overlayWindow.orderOut(nil)
            } else {
                print("[TypeFlow-Debug] Showing overlay window")
                self.repositionWindow()
                self.overlayWindow.orderFront(nil)
            }
        }
    }
}
