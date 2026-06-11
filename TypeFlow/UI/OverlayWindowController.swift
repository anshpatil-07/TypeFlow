import Cocoa
import SwiftUI

class CompletionModel: ObservableObject {
    @Published var text: String = ""
    @Published var isSpellCorrection: Bool = false
    @Published var isRewrite: Bool = false
    @Published var isLoading: Bool = false
    @Published var isSmartReply: Bool = false
    @Published var smartReplyOptions: [String] = []
}

struct SmartReplyOptionsView: View {
    let options: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Smart Replies:")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
            ForEach(options, id: \.self) { option in
                Button {
                    CompletionManager.shared.acceptSmartReply(text: option)
                } label: {
                    Text(option)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.blue.opacity(0.1))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.95))
                .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 2)
        )
        .focusable(false)
    }
}

// ─── Rewrite Mode Selector Bar ────────────────────────────────────────────────
// Shown as soon as the hotkey fires, before LLM responds.
struct RewriteModeBarView: View {
    var body: some View {
        HStack(spacing: 6) {
            Text("Rewrite as:")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            RewriteModeButton(label: "✦ Professional", color: Color(hue: 0.62, saturation: 0.7, brightness: 0.85)) {
                CompletionManager.shared.triggerRewrite(mode: .professional)
            }
            RewriteModeButton(label: "✂ Shorter", color: Color(hue: 0.13, saturation: 0.8, brightness: 0.88)) {
                CompletionManager.shared.triggerRewrite(mode: .shorter)
            }
            RewriteModeButton(label: "✓ Fix Grammar", color: Color(hue: 0.36, saturation: 0.7, brightness: 0.75)) {
                CompletionManager.shared.triggerRewrite(mode: .fixGrammar)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.95))
                .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 2)
        )
        .focusable(false)
    }
}

struct RewriteModeButton: View {
    let label: String
    let color: Color
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button {
            action()
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(color.opacity(hovered ? 1.0 : 0.85))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

// ─── Normal Ghost-Text Overlay ────────────────────────────────────────────────
struct CompletionOverlayView: View {
    @ObservedObject var model: CompletionModel

    var body: some View {
        Group {
            if model.isSmartReply && !model.smartReplyOptions.isEmpty {
                SmartReplyOptionsView(options: model.smartReplyOptions)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else if model.isLoading && (model.isRewrite || model.isSmartReply) {
                if model.text == "Generating..." {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 14, height: 14)
                        Text(model.isSmartReply ? "Generating options..." : "Rewriting...")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(NSColor.windowBackgroundColor).opacity(0.95))
                            .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 2)
                    )
                    .font(.system(size: 13, weight: .regular))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                } else if model.isRewrite {
                    // Show mode selector while waiting for selection to arrive
                    RewriteModeBarView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
            } else if model.text.isEmpty && !model.isLoading {
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

                    Text(model.isLoading ? "Rewriting…" : model.text)
                        .foregroundColor(model.isRewrite ? Color.primary
                                         : (model.isSpellCorrection ? Color.orange : Color.secondary))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(NSColor.windowBackgroundColor).opacity(0.92))
                        .shadow(color: .black.opacity(0.14), radius: 4, x: 0, y: 1)
                )
                .font(.system(size: 13, weight: .regular))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .focusable(false)
    }
}

// ─── Custom Window Subclass ──────────────────────────────────────────────────
class OverlayWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let keyCode = event.keyCode
        if keyCode == 48 { // Tab
            if CompletionManager.shared.activeRewriteText != nil && CompletionManager.shared.currentCompletion != nil {
                print("[TypeFlow-Debug] OverlayWindow performKeyEquivalent: Intercepted Tab during rewrite")
                DispatchQueue.main.async {
                    _ = CompletionManager.shared.handleTabPressed()
                }
                return true // swallow
            }
        }
        if keyCode == 53 { // Escape
            if CompletionManager.shared.isRewrite || CompletionManager.shared.isSmartReply {
                print("[TypeFlow-Debug] OverlayWindow performKeyEquivalent: Intercepted Escape")
                DispatchQueue.main.async {
                    CompletionManager.shared.clearCompletion()
                }
                return true // swallow
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        let keyCode = event.keyCode
        if keyCode == 48 {
            if CompletionManager.shared.isRewrite {
                print("[TypeFlow-Debug] OverlayWindow keyDown: Intercepted Tab during rewrite")
                _ = CompletionManager.shared.handleTabPressed()
                return
            }
        }
        if keyCode == 53 {
            if CompletionManager.shared.isRewrite || CompletionManager.shared.isSmartReply {
                print("[TypeFlow-Debug] OverlayWindow keyDown: Intercepted Escape")
                CompletionManager.shared.clearCompletion()
                return
            }
        }
        super.keyDown(with: event)
    }
}

// ─── Custom Content View for High-Performance Ghost Text ─────────────────────
class OverlayContentView: NSView {
    let textLayer = CATextLayer()
    var hostingView: NSHostingView<CompletionOverlayView>?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
        self.layer?.cornerRadius = 5
        self.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.92).cgColor
        self.layer?.shadowColor = NSColor.black.cgColor
        self.layer?.shadowOpacity = 0.14
        self.layer?.shadowRadius = 4
        self.layer?.shadowOffset = CGSize(width: 0, height: -1)
        
        textLayer.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        textLayer.fontSize = 13
        textLayer.foregroundColor = NSColor.secondaryLabelColor.cgColor
        textLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        textLayer.alignmentMode = .left
        
        // Disable implicit animations
        textLayer.actions = [
            "contents": NSNull(),
            "bounds": NSNull(),
            "position": NSNull(),
            "string": NSNull(),
            "hidden": NSNull()
        ]
        
        self.layer?.addSublayer(textLayer)
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    override func layout() {
        super.layout()
        // Center text vertically.
        // For a 13pt font, 16pt height is appropriate.
        textLayer.frame = CGRect(x: 6, y: (bounds.height - 16) / 2 - 1, width: bounds.width - 12, height: 16)
        hostingView?.frame = bounds
    }
    
    func configure(text: String, isSpellCorrection: Bool, isRewrite: Bool, isLoading: Bool, isSmartReply: Bool, model: CompletionModel) {
        let useSwiftUI = isRewrite || isLoading || isSmartReply
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if useSwiftUI {
            textLayer.isHidden = true
            self.layer?.backgroundColor = NSColor.clear.cgColor
            self.layer?.shadowOpacity = 0
            
            if hostingView == nil {
                let hv = NSHostingView(rootView: CompletionOverlayView(model: model))
                hv.frame = self.bounds
                self.addSubview(hv)
                self.hostingView = hv
            }
        } else {
            textLayer.isHidden = false
            self.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.92).cgColor
            self.layer?.shadowOpacity = 0.14
            
            hostingView?.removeFromSuperview()
            hostingView = nil
            
            textLayer.string = text
            textLayer.foregroundColor = isSpellCorrection ? NSColor.systemOrange.cgColor : NSColor.secondaryLabelColor.cgColor
        }
        CATransaction.commit()
    }
}

// ─── Window Controller ────────────────────────────────────────────────────────
class OverlayWindowController: NSWindowController {
    var overlayWindow: OverlayWindow!
    private let completionModel = CompletionModel()
    private var overlayContentView: OverlayContentView!
    private var lastCaretRect = CGRect.zero
    private var localEventMonitor: Any?

    init() {
        overlayContentView = OverlayContentView(frame: CGRect(x: 0, y: 0, width: 360, height: 28))

        overlayWindow = OverlayWindow(
            contentRect: CGRect(x: 0, y: 0, width: 360, height: 32),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        overlayWindow.level = .screenSaver
        overlayWindow.backgroundColor = .clear
        // Rewrite mode bar needs mouse events; ghost-text overlay ignores them
        overlayWindow.ignoresMouseEvents = false
        overlayWindow.isOpaque = false
        overlayWindow.contentView = overlayContentView
        overlayWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        super.init(window: overlayWindow)

        // Setup local event monitor to intercept Tab/Escape when TypeFlow is key
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = event.keyCode
            if keyCode == 48 { // Tab
                if CompletionManager.shared.isRewrite {
                    print("[TypeFlow-Debug] Local event monitor: Intercepted Tab during rewrite")
                    DispatchQueue.main.async {
                        _ = CompletionManager.shared.handleTabPressed()
                    }
                    return nil // swallow
                }
            }
            if keyCode == 53 { // Escape
                if CompletionManager.shared.isRewrite || CompletionManager.shared.isSmartReply {
                    print("[TypeFlow-Debug] Local event monitor: Intercepted Escape")
                    DispatchQueue.main.async {
                        CompletionManager.shared.clearCompletion()
                    }
                    return nil // swallow
                }
            }
            return event
        }
    }

    deinit {
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func moveOverlay(to rect: CGRect) {
        lastCaretRect = rect
        repositionWindow()
    }

    private func repositionWindow() {
        guard !completionModel.text.isEmpty || completionModel.isLoading || (!completionModel.smartReplyOptions.isEmpty && completionModel.isSmartReply) else { return }

        // Rewrite mode bar is wider and taller (but not when actually generating/showing spinner)
        let isRewriteBar = completionModel.isLoading && completionModel.isRewrite && completionModel.text != "Generating..."
        let isSmartReplyList = completionModel.isSmartReply && !completionModel.smartReplyOptions.isEmpty
        let windowWidth: CGFloat
        let windowHeight: CGFloat

        if isSmartReplyList {
            windowHeight = CGFloat(30 + (completionModel.smartReplyOptions.count * 32))
            windowWidth = 360
        } else if isRewriteBar {
            windowHeight = 36
            windowWidth = 360
        } else {
            windowHeight = 28
            let font = NSFont.systemFont(ofSize: 13, weight: .regular)
            let attributes = [NSAttributedString.Key.font: font]
            let measureText = (completionModel.isLoading && (completionModel.isRewrite || completionModel.isSmartReply)) ? "Rewriting..." : (completionModel.isLoading ? "Rewriting…" : completionModel.text)
            var w = (measureText as NSString).size(withAttributes: attributes).width + 20
            if completionModel.isRewrite && !completionModel.isLoading { w += 68 }
            windowWidth = w
        }

        let displayBounds = CGDisplayBounds(CGMainDisplayID())
        let displayHeight = displayBounds.height
        
        // Default: draw below the caret
        var flippedY = displayHeight - lastCaretRect.origin.y - lastCaretRect.height - windowHeight - 4
        
        // If it goes below the screen (flippedY < 0), draw it ABOVE the caret instead
        if flippedY < 0 {
            flippedY = displayHeight - lastCaretRect.origin.y + 4
            print("[TypeFlow-Debug] OverlayWindowController: Window flipped above caret due to bounds")
        }

        let newFrame = CGRect(
            x: lastCaretRect.origin.x,
            y: flippedY,
            width: windowWidth,
            height: windowHeight
        )
        print("[TypeFlow-Debug] OverlayWindowController frame: \(newFrame) text: '\(completionModel.text)'")
        overlayWindow.setFrame(newFrame, display: true)
    }

    func updateText(_ newText: String,
                    isSpellCorrection: Bool = false,
                    isRewrite: Bool = false,
                    isLoading: Bool = false,
                    isSmartReply: Bool = false,
                    smartReplyOptions: [String] = []) {
        print("[TypeFlow-Debug] OverlayWindowController updateText '\(newText)' spell:\(isSpellCorrection) rewrite:\(isRewrite) loading:\(isLoading) smartReply:\(isSmartReply)")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.completionModel.isSpellCorrection = isSpellCorrection
            self.completionModel.isRewrite = isRewrite
            self.completionModel.isLoading = isLoading
            self.completionModel.isSmartReply = isSmartReply
            self.completionModel.smartReplyOptions = smartReplyOptions
            self.completionModel.text = newText
            
            self.overlayContentView.configure(text: newText, isSpellCorrection: isSpellCorrection, isRewrite: isRewrite, isLoading: isLoading, isSmartReply: isSmartReply, model: self.completionModel)
            
            // Allow mouse events only for the rewrite mode bar and smart reply list
            self.overlayWindow.ignoresMouseEvents = !((isLoading && isRewrite) || (isSmartReply && !smartReplyOptions.isEmpty))
            if newText.isEmpty && !isLoading && smartReplyOptions.isEmpty {
                self.overlayWindow.orderOut(nil)
            } else {
                self.repositionWindow()
                self.overlayWindow.orderFront(nil)
            }
        }
    }
}
