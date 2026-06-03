import Cocoa
import SwiftUI

class CompletionModel: ObservableObject {
    @Published var text: String = ""
    @Published var isSpellCorrection: Bool = false
    @Published var isRewrite: Bool = false
    @Published var isLoading: Bool = false
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
    }
}

struct RewriteModeButton: View {
    let label: String
    let color: Color
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
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
        if model.isLoading && model.isRewrite {
            if model.text == "Generating..." {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                    Text("Rewriting...")
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
            } else {
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
}

// ─── Window Controller ────────────────────────────────────────────────────────
class OverlayWindowController: NSWindowController {
    var overlayWindow: NSWindow!
    private let completionModel = CompletionModel()
    private var lastCaretRect = CGRect.zero

    init() {
        let hostingView = NSHostingView(rootView: CompletionOverlayView(model: completionModel))

        overlayWindow = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 360, height: 32),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        overlayWindow.level = .floating
        overlayWindow.backgroundColor = .clear
        // Rewrite mode bar needs mouse events; ghost-text overlay ignores them
        overlayWindow.ignoresMouseEvents = false
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

        // Rewrite mode bar is wider and taller (but not when actually generating/showing spinner)
        let isRewriteBar = completionModel.isLoading && completionModel.isRewrite && completionModel.text != "Generating..."
        let windowWidth: CGFloat
        let windowHeight: CGFloat = isRewriteBar ? 36 : 28

        if isRewriteBar {
            windowWidth = 360
        } else {
            let font = NSFont.systemFont(ofSize: 13, weight: .regular)
            let attributes = [NSAttributedString.Key.font: font]
            let measureText = (completionModel.isLoading && completionModel.isRewrite) ? "Rewriting..." : (completionModel.isLoading ? "Rewriting…" : completionModel.text)
            var w = (measureText as NSString).size(withAttributes: attributes).width + 20
            if completionModel.isRewrite && !completionModel.isLoading { w += 68 }
            windowWidth = w
        }

        // Flip Y: AX uses top-left origin; macOS screen uses bottom-left
        let displayHeight = CGDisplayBounds(CGMainDisplayID()).height
        let flippedY = displayHeight - lastCaretRect.origin.y - lastCaretRect.height - windowHeight - 4

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
                    isLoading: Bool = false) {
        print("[TypeFlow-Debug] OverlayWindowController updateText '\(newText)' spell:\(isSpellCorrection) rewrite:\(isRewrite) loading:\(isLoading)")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.completionModel.isSpellCorrection = isSpellCorrection
            self.completionModel.isRewrite = isRewrite
            self.completionModel.isLoading = isLoading
            self.completionModel.text = newText
            // Allow mouse events only for the rewrite mode bar
            self.overlayWindow.ignoresMouseEvents = !(isLoading && isRewrite)
            if newText.isEmpty && !isLoading {
                self.overlayWindow.orderOut(nil)
            } else {
                self.repositionWindow()
                self.overlayWindow.orderFront(nil)
            }
        }
    }
}
