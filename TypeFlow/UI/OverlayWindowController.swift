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

class OverlayWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func becomeKey() {
        print("[TypeFlow-InputAudit] overlayWindowEvent=becomeKey visible=\(isVisible) key=\(isKeyWindow) main=\(isMainWindow)")
        super.becomeKey()
    }

    override func becomeMain() {
        print("[TypeFlow-InputAudit] overlayWindowEvent=becomeMain visible=\(isVisible) key=\(isKeyWindow) main=\(isMainWindow)")
        super.becomeMain()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let keyCode = event.keyCode
        if keyCode == 48 { // Tab
            if CompletionManager.shared.activeRewriteText != nil && CompletionManager.shared.currentCompletion != nil {
                print("[TypeFlow-Debug] OverlayWindow performKeyEquivalent: Intercepted Tab during rewrite")
                DispatchQueue.main.async {
                    _ = CompletionManager.shared.handleTabPressed()
                }
                return true
            }
        }
        if keyCode == 53 { // Escape
            if CompletionManager.shared.isRewrite || CompletionManager.shared.isSmartReply {
                print("[TypeFlow-Debug] OverlayWindow performKeyEquivalent: Intercepted Escape")
                DispatchQueue.main.async {
                    CompletionManager.shared.clearCompletion()
                }
                return true
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

// ─── Support Models from Cotabby ──────────────────────────────────────────

enum CaretGeometryQuality: String, Equatable {
    case exact
    case derived
    case estimated
    case layoutEstimated
}

struct ResolvedFieldStyle: Equatable {
    let fontName: String?
    let fontPointSize: CGFloat?
    let colorHex: String?
    
    var isEmpty: Bool {
        fontName == nil && colorHex == nil
    }
}

struct SuggestionOverlayGeometry: Equatable {
    let caretRect: CGRect
    let inputFrameRect: CGRect?
    let caretQuality: CaretGeometryQuality
    let isCaretAtEndOfLine: Bool
    let observedCharWidth: CGFloat?
    let isRightToLeft: Bool
    let focusChangeSequence: UInt64
    let focusedInputIdentityKey: UInt64
    let isCorrection: Bool
    let resolvedFieldStyle: ResolvedFieldStyle?
    
    func withCaretRect(_ caretRect: CGRect) -> SuggestionOverlayGeometry {
        SuggestionOverlayGeometry(
            caretRect: caretRect,
            inputFrameRect: inputFrameRect,
            caretQuality: caretQuality,
            isCaretAtEndOfLine: isCaretAtEndOfLine,
            observedCharWidth: observedCharWidth,
            isRightToLeft: isRightToLeft,
            focusChangeSequence: focusChangeSequence,
            focusedInputIdentityKey: focusedInputIdentityKey,
            isCorrection: isCorrection,
            resolvedFieldStyle: resolvedFieldStyle
        )
    }
}

struct GhostFontSizeStabilizer {
    private var sessionKey: UInt64?
    private var minCaretHeight: CGFloat?

    mutating func stabilizedCaretHeight(_ caretHeight: CGFloat, focusSessionKey: UInt64) -> CGFloat {
        guard caretHeight > 0 else {
            return caretHeight
        }

        if sessionKey != focusSessionKey {
            sessionKey = focusSessionKey
            minCaretHeight = caretHeight
            return caretHeight
        }

        let stabilized = min(caretHeight, minCaretHeight ?? caretHeight)
        minCaretHeight = stabilized
        return stabilized
    }
}

enum GhostFontMetrics {
    static let absoluteMinimumPointSize: CGFloat = 9

    struct FieldFontMetrics: Equatable {
        let pointSize: CGFloat
        let ascender: CGFloat
        let descender: CGFloat
    }

    static func pointSize(
        caretHeight: CGFloat,
        fieldMetrics: FieldFontMetrics?,
        fallbackRatio: CGFloat,
        minimum: CGFloat,
        maximum: CGFloat,
        sizeMultiplier: CGFloat = 1
    ) -> CGFloat {
        let ratio = metricRatio(fieldMetrics) ?? fallbackRatio
        let autoSize = min(max(minimum, caretHeight * ratio), maximum)
        return max(absoluteMinimumPointSize, autoSize * sizeMultiplier)
    }

    private static func metricRatio(_ metrics: FieldFontMetrics?) -> CGFloat? {
        guard let metrics, metrics.pointSize > 0 else {
            return nil
        }

        let glyphBoxHeight = metrics.ascender - metrics.descender
        guard glyphBoxHeight > 0 else {
            return nil
        }

        return metrics.pointSize / glyphBoxHeight
    }
}

struct GhostSuggestionLayout: Equatable {
    struct Line: Equatable, Identifiable {
        let index: Int
        let text: String
        let leadingIndent: CGFloat
        let showsKeycap: Bool

        var id: Int { index }
    }

    let lines: [Line]
    let panelOriginX: CGFloat
    let lineHeight: CGFloat
    let topLineCenterOffsetFromCaret: CGFloat
    let isRightToLeft: Bool

    private enum Metrics {
        static let caretGap: CGFloat = 4
        static let inputHorizontalPadding: CGFloat = 8
        static let fallbackScreenMargin: CGFloat = 16
        static let minimumLineWidth: CGFloat = 48
        static let estimatedKeycapAndSpacingWidth: CGFloat = 36
        static let lineHeightMultiplier: CGFloat = 1.25
    }

    private struct TextMeasure {
        let fontSize: CGFloat
        let observedCharWidth: CGFloat?
        let font: NSFont?
    }

    static func make(
        text: String,
        geometry: SuggestionOverlayGeometry,
        fontSize: CGFloat,
        visibleFrame: CGRect,
        showsAcceptanceHint: Bool = false,
        font: NSFont? = nil
    ) -> GhostSuggestionLayout {
        let normalizedText = normalizedDisplayText(text)
        let lineHeight = ceil(fontSize * Metrics.lineHeightMultiplier)
        let isRTL = geometry.isRightToLeft
        let measure = TextMeasure(
            fontSize: fontSize,
            observedCharWidth: geometry.observedCharWidth,
            font: font
        )
        let keycapReservation = showsAcceptanceHint ? Metrics.estimatedKeycapAndSpacingWidth : 0
        let usableFrame = usableTextFrame(
            geometry: geometry,
            visibleFrame: visibleFrame
        )

        let firstLineAnchor: CGFloat
        let firstLineBudget: CGFloat
        if isRTL {
            firstLineAnchor = min(
                max(geometry.caretRect.minX - Metrics.caretGap, usableFrame.minX),
                usableFrame.maxX
            )
            firstLineBudget = max(
                0,
                firstLineAnchor - usableFrame.minX - keycapReservation
            )
        } else {
            firstLineAnchor = min(
                max(geometry.caretRect.maxX + Metrics.caretGap, usableFrame.minX),
                usableFrame.maxX
            )
            firstLineBudget = max(
                0,
                usableFrame.maxX - firstLineAnchor - keycapReservation
            )
        }

        let overflowBudget = max(
            Metrics.minimumLineWidth,
            usableFrame.width - keycapReservation
        )

        let singleLineFits = !normalizedText.contains("\n")
            && measuredWidth(of: normalizedText, using: measure) <= firstLineBudget

        if singleLineFits {
            return GhostSuggestionLayout(
                lines: [
                    Line(index: 0, text: normalizedText, leadingIndent: 0, showsKeycap: showsAcceptanceHint)
                ],
                panelOriginX: firstLineAnchor,
                lineHeight: lineHeight,
                topLineCenterOffsetFromCaret: 0,
                isRightToLeft: isRTL
            )
        }

        let panelOriginX = isRTL ? usableFrame.maxX : usableFrame.minX
        var remainingText = normalizedText
        var rawLines: [(text: String, leadingIndent: CGFloat)] = []
        var startsBelowCaret = false

        if firstLineBudget >= Metrics.minimumLineWidth {
            let split = splitPrefix(
                from: remainingText,
                maxWidth: firstLineBudget,
                using: measure
            )
            if !split.line.isEmpty {
                let indent: CGFloat
                if isRTL {
                    indent = panelOriginX - firstLineAnchor
                } else {
                    indent = firstLineAnchor - panelOriginX
                }
                rawLines.append((split.line, indent))
                remainingText = split.remainder
            } else {
                startsBelowCaret = true
            }
        } else {
            startsBelowCaret = true
        }

        while !remainingText.isEmpty {
            let split = splitPrefix(
                from: remainingText,
                maxWidth: overflowBudget,
                using: measure
            )
            guard !split.line.isEmpty else {
                break
            }

            rawLines.append((split.line, 0))
            remainingText = split.remainder
        }

        if rawLines.isEmpty {
            rawLines.append((normalizedText, 0))
            startsBelowCaret = true
        }

        let finalLines = rawLines.enumerated().map { offset, rawLine in
            Line(
                index: offset,
                text: rawLine.text,
                leadingIndent: rawLine.leadingIndent,
                showsKeycap: showsAcceptanceHint && offset == rawLines.count - 1
            )
        }

        return GhostSuggestionLayout(
            lines: finalLines,
            panelOriginX: panelOriginX,
            lineHeight: lineHeight,
            topLineCenterOffsetFromCaret: startsBelowCaret ? -lineHeight : 0,
            isRightToLeft: isRTL
        )
    }

    func panelFrame(for contentSize: CGSize, caretRect: CGRect) -> CGRect {
        let topLineCenterY = caretRect.midY + topLineCenterOffsetFromCaret
        let originY = topLineCenterY - contentSize.height + (lineHeight / 2)
        let originX = isRightToLeft ? panelOriginX - contentSize.width : panelOriginX

        return CGRect(
            origin: CGPoint(x: originX, y: originY),
            size: contentSize
        )
    }

    private static func usableTextFrame(
        geometry: SuggestionOverlayGeometry,
        visibleFrame: CGRect
    ) -> CGRect {
        if let inputFrame = geometry.inputFrameRect?.standardized,
           inputFrame.width > Metrics.minimumLineWidth {
            let minX = max(
                inputFrame.minX + Metrics.inputHorizontalPadding,
                visibleFrame.minX + Metrics.fallbackScreenMargin
            )
            let maxX = min(
                inputFrame.maxX - Metrics.inputHorizontalPadding,
                visibleFrame.maxX - Metrics.fallbackScreenMargin
            )

            if maxX - minX > Metrics.minimumLineWidth {
                return CGRect(
                    x: minX,
                    y: inputFrame.minY,
                    width: maxX - minX,
                    height: inputFrame.height
                )
            }
        }

        let fallbackMinX: CGFloat
        let fallbackMaxX: CGFloat
        if geometry.isRightToLeft {
            fallbackMinX = visibleFrame.minX + Metrics.fallbackScreenMargin
            fallbackMaxX = geometry.caretRect.minX - Metrics.caretGap
        } else {
            fallbackMinX = geometry.caretRect.maxX + Metrics.caretGap
            fallbackMaxX = visibleFrame.maxX - Metrics.fallbackScreenMargin
        }

        return CGRect(
            x: fallbackMinX,
            y: geometry.caretRect.minY,
            width: max(Metrics.minimumLineWidth, fallbackMaxX - fallbackMinX),
            height: geometry.caretRect.height
        )
    }

    static func renderedWidth(of text: String, font: NSFont) -> CGFloat {
        let display = normalizedDisplayText(text)
        guard !display.isEmpty else { return 0 }
        return (display as NSString).size(withAttributes: [.font: font]).width
    }

    private static func normalizedDisplayText(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let normalizedLines = lines.map { line -> String in
            let words = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard !words.isEmpty else { return "" }
            let joined = words.joined(separator: " ")
            return line.first?.isWhitespace == true ? " \(joined)" : joined
        }
        return normalizedLines.joined(separator: "\n")
    }

    private static func splitPrefix(
        from text: String,
        maxWidth: CGFloat,
        using measure: TextMeasure
    ) -> (line: String, remainder: String) {
        let source = text.trimmingCharacters(in: .whitespaces)
        guard !source.isEmpty else {
            return ("", "")
        }

        let safeMaxWidth = max(maxWidth, Metrics.minimumLineWidth)

        if let newlineIndex = source.firstIndex(of: "\n") {
            return splitAtNewline(
                source: source,
                newlineIndex: newlineIndex,
                maxWidth: maxWidth,
                using: measure
            )
        }

        if measuredWidth(of: source, using: measure) <= safeMaxWidth {
            return (source, "")
        }

        let characters = Array(source)
        var lastWhitespaceBreak: Int?

        for endIndex in characters.indices {
            let prefix = String(characters[...endIndex])
            if characters[endIndex].isWhitespace {
                lastWhitespaceBreak = endIndex + 1
            }

            if measuredWidth(of: prefix, using: measure) > safeMaxWidth {
                if let breakIndex = lastWhitespaceBreak, breakIndex > 0 {
                    let line = String(characters[..<breakIndex])
                        .trimmingCharacters(in: .whitespaces)
                    let remainder = String(characters[breakIndex...])
                        .trimmingCharacters(in: .whitespaces)
                    return (line, remainder)
                }

                let splitIndex = max(endIndex, 1)
                let line = String(characters[..<splitIndex])
                    .trimmingCharacters(in: .whitespaces)
                let remainder = String(characters[splitIndex...])
                    .trimmingCharacters(in: .whitespaces)
                return (line, remainder)
            }
        }

        return (text.trimmingCharacters(in: .whitespaces), "")
    }

    private static func splitAtNewline(
        source: String,
        newlineIndex: String.Index,
        maxWidth: CGFloat,
        using measure: TextMeasure
    ) -> (line: String, remainder: String) {
        let safeMaxWidth = max(maxWidth, Metrics.minimumLineWidth)
        let segment = String(source[..<newlineIndex]).trimmingCharacters(in: .whitespaces)
        let afterIndex = source.index(after: newlineIndex)
        let afterNewline = afterIndex < source.endIndex
            ? String(source[afterIndex...]).trimmingCharacters(in: .whitespaces)
            : ""

        guard !segment.isEmpty else {
            return splitPrefix(from: afterNewline, maxWidth: maxWidth, using: measure)
        }

        if measuredWidth(of: segment, using: measure) <= safeMaxWidth {
            return (segment, afterNewline)
        }

        let widthSplit = splitPrefix(from: segment, maxWidth: maxWidth, using: measure)
        let combined: String
        if widthSplit.remainder.isEmpty {
            combined = afterNewline
        } else if afterNewline.isEmpty {
            combined = widthSplit.remainder
        } else {
            combined = widthSplit.remainder + "\n" + afterNewline
        }
        return (widthSplit.line, combined)
    }

    private static func measuredWidth(of text: String, using measure: TextMeasure) -> CGFloat {
        if let observedCharWidth = measure.observedCharWidth, observedCharWidth > 0 {
            return CGFloat((text as NSString).length) * observedCharWidth
        }

        return (text as NSString).size(withAttributes: [
            .font: measure.font ?? NSFont.systemFont(ofSize: measure.fontSize)
        ]).width
    }
}

struct GhostSuggestionView: View {
    @Environment(\.colorScheme) var colorScheme
    let layout: GhostSuggestionLayout
    let fontSize: CGFloat
    let fieldFont: NSFont?
    let fieldColor: Color?
    let customColor: Color?
    let keycapLabel: String?
    let opacity: Double
    let isCorrection: Bool

    var ghostColor: Color {
        if isCorrection {
            return (colorScheme == .dark
                ? Color(red: 0.45, green: 0.85, blue: 0.45)
                : Color(red: 0.15, green: 0.60, blue: 0.20)).opacity(opacity)
        }
        let baseColor = customColor
            ?? fieldColor
            ?? Color.secondary
        return baseColor.opacity(opacity)
    }

    private var resolvedFont: Font {
        if let fieldFont {
            return Font(fieldFont as CTFont)
        }
        return .system(size: fontSize)
    }

    var body: some View {
        let alignment: HorizontalAlignment = layout.isRightToLeft ? .trailing : .leading
        VStack(alignment: alignment, spacing: 0) {
            ForEach(layout.lines) { line in
                let showsKeycap = line.showsKeycap && keycapLabel != nil
                HStack(alignment: .firstTextBaseline, spacing: showsKeycap ? 6 : 0) {
                    if layout.isRightToLeft, showsKeycap, let keycapLabel {
                        GhostKeycap(label: keycapLabel)
                    }

                    Text(line.text)
                        .font(resolvedFont)
                        .foregroundStyle(ghostColor)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: true)

                    if !layout.isRightToLeft, showsKeycap, let keycapLabel {
                        GhostKeycap(label: keycapLabel)
                    }
                }
                .padding(layout.isRightToLeft ? .trailing : .leading, line.leadingIndent)
                .fixedSize(horizontal: true, vertical: true)
            }
        }
        .fixedSize(horizontal: true, vertical: true)
    }
}

private struct GhostKeycap: View {
    @Environment(\.colorScheme) var colorScheme
    let label: String

    var textColor: Color {
        colorScheme == .dark ? Color(white: 0.65) : Color(white: 0.45)
    }

    var bgColor: Color {
        colorScheme == .dark ? Color(white: 0.18) : Color(white: 0.95)
    }

    var borderColor: Color {
        colorScheme == .dark ? Color(white: 0.3) : Color(white: 0.8)
    }

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(textColor)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(bgColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
            .fixedSize(horizontal: true, vertical: true)
    }
}

// ─── Window Controller ────────────────────────────────────────────────────────

class OverlayWindowController: NSWindowController {
    private enum PendingOverlayMutation {
        case updateText(
            text: String,
            isSpellCorrection: Bool,
            isRewrite: Bool,
            isLoading: Bool,
            isSmartReply: Bool,
            smartReplyOptions: [String]
        )
        case updateGhostText(text: String, isStale: Bool)
        case updateAutocompleteText(text: String, requestID: UInt64)
        case replaceGhostTextAfterAcceptance(inserted: String, remainder: String, source: String)
    }

    private struct PendingAutocompleteRender {
        let requestID: UInt64
        let text: String
        let requestedAt: CFAbsoluteTime
    }

    var overlayWindow: OverlayWindow!
    private let completionModel = CompletionModel()
    private var lastCaretRect = CGRect.zero
    private var localEventMonitor: Any?

    private var inlineHostingView: NSHostingView<GhostSuggestionView>?
    private var completionOverlayHostingView: NSHostingView<CompletionOverlayView>?
    
    private var ghostFontStabilizer = GhostFontSizeStabilizer()
    private var lastInlineRenderFont: NSFont?
    private var lastInlineFontSize: CGFloat?
    private var lastGeometry: SuggestionOverlayGeometry?
    
    private var lastFocusedPID: pid_t = 0
    private var focusSessionKey: UInt64 = 0
    private var pendingMoveOverlayRect: CGRect?
    private var pendingShiftOverlayX: CGFloat = 0
    private var pendingOverlayMutation: PendingOverlayMutation?
    private var isDeferredOverlayFlushScheduled = false
    private var pendingAutocompleteRender: PendingAutocompleteRender?
    private var isAutocompleteRenderFlushScheduled = false
    private var lastRenderedAutocompleteText: String = ""
    private var lastRenderedAutocompleteRequestID: UInt64?

    private func overlaySubviewCount() -> Int {
        func countSubviews(in view: NSView?) -> Int {
            guard let view = view else { return 0 }
            return view.subviews.count + view.subviews.reduce(0) { $0 + countSubviews(in: $1) }
        }
        return countSubviews(in: overlayWindow.contentView)
    }

    private func overlayLayerCount() -> Int {
        func countLayers(in layer: CALayer?) -> Int {
            guard let layer = layer else { return 0 }
            let sublayers = layer.sublayers ?? []
            return sublayers.count + sublayers.reduce(0) { $0 + countLayers(in: $1) }
        }
        return countLayers(in: overlayWindow.contentView?.layer)
    }

    private func clearAllRenderedGhostText(resetGeometry: Bool = false, clearPendingMutations: Bool = false) {
        let oldLayerCount = overlayLayerCount()
        let oldSubviewCount = overlaySubviewCount()
        print("[OverlayRender] clearAllRenderedGhostText oldLayerCount=\(oldLayerCount) oldSubviewCount=\(oldSubviewCount)")

        overlayWindow.contentView?.layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        overlayWindow.contentView?.subviews.forEach { $0.removeFromSuperview() }
        overlayWindow.contentView = nil
        inlineHostingView = nil
        completionOverlayHostingView = nil

        if resetGeometry {
            lastGeometry = nil
        }

        pendingShiftOverlayX = 0
        pendingAutocompleteRender = nil
        isAutocompleteRenderFlushScheduled = false
        lastRenderedAutocompleteText = ""
        lastRenderedAutocompleteRequestID = nil
        if clearPendingMutations {
            pendingMoveOverlayRect = nil
            pendingOverlayMutation = nil
            isDeferredOverlayFlushScheduled = false
        }
    }

    private func logRenderReplace(text: String) {
        print("[OverlayRender] renderReplace text='\(text)' layerCountAfter=\(overlayLayerCount()) subviewCountAfter=\(overlaySubviewCount())")
    }

    private func appKitCaretRect(from caretRect: CGRect) -> CGRect {
        let displayBounds = CGDisplayBounds(CGMainDisplayID())
        let displayHeight = displayBounds.height
        return CGRect(
            x: caretRect.origin.x,
            y: displayHeight - caretRect.origin.y - caretRect.height,
            width: caretRect.width,
            height: caretRect.height
        )
    }

    init() {
        overlayWindow = OverlayWindow(
            contentRect: CGRect(x: 0, y: 0, width: 10, height: 10),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        overlayWindow.isReleasedWhenClosed = false
        overlayWindow.backgroundColor = .clear
        overlayWindow.isOpaque = false
        overlayWindow.ignoresMouseEvents = true
        overlayWindow.hasShadow = false
        overlayWindow.animationBehavior = .none
        overlayWindow.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        overlayWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        super.init(window: overlayWindow)

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = event.keyCode
            if keyCode == 48 { // Tab
                if CompletionManager.shared.isRewrite {
                    print("[TypeFlow-Debug] Local event monitor: Intercepted Tab during rewrite")
                    DispatchQueue.main.async {
                        _ = CompletionManager.shared.handleTabPressed()
                    }
                    return nil
                }
            }
            if keyCode == 53 { // Escape
                if CompletionManager.shared.isRewrite || CompletionManager.shared.isSmartReply {
                    print("[TypeFlow-Debug] Local event monitor: Intercepted Escape")
                    DispatchQueue.main.async {
                        CompletionManager.shared.clearCompletion()
                    }
                    return nil
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

    func focusAuditSummary() -> String {
        let appActive = NSApp.isActive
        let keyWindowIsOverlay = NSApp.keyWindow === overlayWindow
        let mainWindowIsOverlay = NSApp.mainWindow === overlayWindow
        return "visible=\(overlayWindow.isVisible) key=\(overlayWindow.isKeyWindow) main=\(overlayWindow.isMainWindow) appActive=\(appActive) keyWindowIsOverlay=\(keyWindowIsOverlay) mainWindowIsOverlay=\(mainWindowIsOverlay)"
    }

    private func scheduleDeferredOverlayFlush() {
        guard !isDeferredOverlayFlushScheduled else { return }
        isDeferredOverlayFlushScheduled = true

        InputCriticalSection.shared.runWhenSafe { [weak self] in
            self?.flushDeferredOverlayMutation()
        }
    }

    private func deferMoveOverlayIfNeeded(to rect: CGRect) -> Bool {
        guard InputCriticalSection.shared.isActive else { return false }
        pendingMoveOverlayRect = rect
        print("[InputCriticalSection] overlay update blocked/deferred because physical key is down action=moveOverlay")
        scheduleDeferredOverlayFlush()
        return true
    }

    private func deferShiftOverlayIfNeeded(by points: CGFloat) -> Bool {
        guard InputCriticalSection.shared.isActive else { return false }
        pendingShiftOverlayX += points
        print("[InputCriticalSection] overlay update blocked/deferred because physical key is down action=shiftOverlayX points=\(String(format: "%.2f", points))")
        scheduleDeferredOverlayFlush()
        return true
    }

    private func deferOverlayMutationIfNeeded(_ mutation: PendingOverlayMutation, action: String) -> Bool {
        guard InputCriticalSection.shared.isActive else { return false }
        if pendingShiftOverlayX != 0 {
            print("[OverlayRender] prevented additive overlay render")
        }
        pendingShiftOverlayX = 0
        pendingOverlayMutation = mutation
        print("[InputCriticalSection] overlay update blocked/deferred because physical key is down action=\(action)")
        scheduleDeferredOverlayFlush()
        return true
    }

    private func flushDeferredOverlayMutation() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            if InputCriticalSection.shared.isActive {
                self.isDeferredOverlayFlushScheduled = false
                self.scheduleDeferredOverlayFlush()
                return
            }

            let moveRect = self.pendingMoveOverlayRect
            let mutation = self.pendingOverlayMutation
            let shiftX = mutation == nil ? self.pendingShiftOverlayX : 0
            if mutation != nil && self.pendingShiftOverlayX != 0 {
                print("[OverlayRender] prevented additive overlay render")
            }

            self.pendingMoveOverlayRect = nil
            self.pendingShiftOverlayX = 0
            self.pendingOverlayMutation = nil
            self.isDeferredOverlayFlushScheduled = false

            guard moveRect != nil || shiftX != 0 || mutation != nil else { return }
            print("[InputCriticalSection] flushed/deferred overlay update after keyUp move=\(moveRect != nil) shift=\(shiftX != 0) mutation=\(mutation != nil)")

            if let moveRect {
                self.applyMoveOverlay(to: moveRect)
            }

            if shiftX != 0 {
                self.applyShiftOverlayX(by: shiftX)
            }

            switch mutation {
            case .updateText(let text, let isSpellCorrection, let isRewrite, let isLoading, let isSmartReply, let smartReplyOptions):
                self.applyUpdateText(
                    text,
                    isSpellCorrection: isSpellCorrection,
                    isRewrite: isRewrite,
                    isLoading: isLoading,
                    isSmartReply: isSmartReply,
                    smartReplyOptions: smartReplyOptions
                )
            case .updateGhostText(let text, let isStale):
                self.applyUpdateGhostText(text, isStale: isStale)
            case .updateAutocompleteText(let text, let requestID):
                self.enqueueAutocompleteRender(text: text, requestID: requestID)
            case .replaceGhostTextAfterAcceptance(let inserted, let remainder, let source):
                self.applyReplaceGhostTextAfterAcceptance(inserted: inserted, remainder: remainder, source: source)
            case .none:
                break
            }
        }
    }

    func moveOverlay(to rect: CGRect) {
        guard InputIsolationMode.current.allowOverlay else {
            print("[TypeFlow-InputIsolation] overlay/window mutation blocked mode=\(InputIsolationMode.current.label) action=moveOverlay")
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard !self.deferMoveOverlayIfNeeded(to: rect) else { return }
            self.applyMoveOverlay(to: rect)
        }
    }

    private func applyMoveOverlay(to rect: CGRect) {
        print("[GeometryProbe] overlayMove source=moveOverlay rect={{x=\(String(format: "%.1f", rect.origin.x)),y=\(String(format: "%.1f", rect.origin.y)),w=\(String(format: "%.1f", rect.width)),h=\(String(format: "%.1f", rect.height))}}")
        lastCaretRect = rect
        if let geom = lastGeometry {
            lastGeometry = geom.withCaretRect(appKitCaretRect(from: rect))
        }
        updateFocusSessionKeyIfNeeded()
        repositionWindow()
    }

    private func updateFocusSessionKeyIfNeeded() {
        let currentPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        if currentPID != lastFocusedPID {
            lastFocusedPID = currentPID
            focusSessionKey = focusSessionKey &+ 1
        }
    }

    private func repositionWindow() {
        guard !completionModel.text.isEmpty || completionModel.isLoading || (!completionModel.smartReplyOptions.isEmpty && completionModel.isSmartReply) else { return }

        let useSwiftUIOverlay = completionModel.isRewrite || completionModel.isSmartReply || completionModel.isLoading
        
        if useSwiftUIOverlay {
            clearAllRenderedGhostText()
            // Rewrite, smart reply, or loading spinner mode
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
            
            var flippedY = displayHeight - lastCaretRect.origin.y - lastCaretRect.height - windowHeight - 4
            
            if flippedY < 0 {
                flippedY = displayHeight - lastCaretRect.origin.y + 4
                // Suppressed: print("[TypeFlow-Debug] OverlayWindowController: Window flipped above caret due to bounds")
            }

            let newFrame = CGRect(
                x: lastCaretRect.origin.x,
                y: flippedY,
                width: windowWidth,
                height: windowHeight
            )
            
            let hv = NSHostingView(rootView: CompletionOverlayView(model: completionModel))
            completionOverlayHostingView = hv
            
            if overlayWindow.contentView !== completionOverlayHostingView {
                overlayWindow.contentView = completionOverlayHostingView
            }
            
            overlayWindow.ignoresMouseEvents = !((completionModel.isLoading && completionModel.isRewrite) || (completionModel.isSmartReply && !completionModel.smartReplyOptions.isEmpty))
            overlayWindow.setFrame(newFrame, display: true)
            logRenderReplace(text: completionModel.text)
        } else {
            _ = renderInlineGhostText(completionModel.text, isStale: false)
        }
    }

    func shiftOverlayX(by points: CGFloat) {
        guard InputIsolationMode.current.allowOverlay else {
            print("[TypeFlow-InputIsolation] overlay/window mutation blocked mode=\(InputIsolationMode.current.label) action=shiftOverlayX")
            return
        }

        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.shiftOverlayX(by: points)
            }
            return
        }

        guard !deferShiftOverlayIfNeeded(by: points) else { return }
        applyShiftOverlayX(by: points)
    }

    private func applyShiftOverlayX(by points: CGFloat) {
        guard overlayWindow.isVisible else { return }
        lastCaretRect.origin.x += points
        if var geom = lastGeometry {
            lastGeometry = geom.withCaretRect(geom.caretRect.offsetBy(dx: points, dy: 0))
        }
        var f = overlayWindow.frame
        f.origin.x += points
        overlayWindow.setFrameOrigin(f.origin)
    }

    func updateAutocompleteText(_ newText: String, requestID: UInt64) {
        guard InputIsolationMode.current.allowOverlay else {
            print("[TypeFlow-InputIsolation] overlay/window mutation blocked mode=\(InputIsolationMode.current.label) action=updateAutocompleteText")
            return
        }

        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.updateAutocompleteText(newText, requestID: requestID)
            }
            return
        }

        print("[RenderPipeline] render requested requestID=\(requestID) textLen=\(newText.count)")
        let mutation = PendingOverlayMutation.updateAutocompleteText(text: newText, requestID: requestID)
        guard !deferOverlayMutationIfNeeded(mutation, action: "updateAutocompleteText") else { return }
        enqueueAutocompleteRender(text: newText, requestID: requestID)
    }

    private func enqueueAutocompleteRender(text: String, requestID: UInt64) {
        if let pending = pendingAutocompleteRender {
            print("[RenderPipeline] coalesced render oldTextLen=\(pending.text.count) newTextLen=\(text.count)")
        }
        pendingAutocompleteRender = PendingAutocompleteRender(
            requestID: requestID,
            text: text,
            requestedAt: CFAbsoluteTimeGetCurrent()
        )

        guard !isAutocompleteRenderFlushScheduled else { return }
        isAutocompleteRenderFlushScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.flushAutocompleteRender()
        }
    }

    private func flushAutocompleteRender() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.flushAutocompleteRender()
            }
            return
        }

        isAutocompleteRenderFlushScheduled = false
        guard let pending = pendingAutocompleteRender else { return }
        pendingAutocompleteRender = nil

        if InputCriticalSection.shared.isActive {
            pendingAutocompleteRender = pending
            scheduleDeferredOverlayFlush()
            return
        }

        applyAutocompleteRender(text: pending.text, requestID: pending.requestID, requestedAt: pending.requestedAt)
    }

    private func applyAutocompleteRender(text: String, requestID: UInt64, requestedAt: CFAbsoluteTime) {
        let startedAt = CFAbsoluteTimeGetCurrent()

        if let lastRequestID = lastRenderedAutocompleteRequestID, requestID < lastRequestID {
            print("[RenderPipeline] skipped stale render requestID=\(requestID)")
            return
        }

        if lastRenderedAutocompleteRequestID == requestID && lastRenderedAutocompleteText == text {
            print("[RenderPipeline] render applied requestID=\(requestID) textLen=\(text.count) durationMs=0.0")
            print("[RenderPipeline] reused existing text layer=true")
            print("[RenderPipeline] layerCountBefore=\(overlayLayerCount()) layerCountAfter=\(overlayLayerCount())")
            print("[RenderPipeline] renderMs=0.0")
            return
        }

        completionModel.isSpellCorrection = false
        completionModel.isRewrite = false
        completionModel.isLoading = false
        completionModel.isSmartReply = false
        completionModel.smartReplyOptions = []
        completionModel.text = text

        if text.isEmpty {
            clearAllRenderedGhostText(resetGeometry: true, clearPendingMutations: true)
            CompletionManager.shared.accessibilityMonitor?.setAcceptTapNeededForVisibleCompletion(false, reason: "updateAutocompleteText-empty")
            print("[TypeFlow-InputAudit] overlayWindowEvent=orderOut source=updateAutocompleteText visibleBefore=\(overlayWindow.isVisible) key=\(overlayWindow.isKeyWindow) main=\(overlayWindow.isMainWindow)")
            overlayWindow.orderOut(nil)
            lastRenderedAutocompleteText = ""
            lastRenderedAutocompleteRequestID = requestID
            let durationMs = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
            print("[RenderPipeline] render applied requestID=\(requestID) textLen=0 durationMs=\(String(format: "%.1f", durationMs))")
            print("[RenderPipeline] renderMs=\(String(format: "%.1f", durationMs))")
            LatencyInstrumentation.shared.renderApplied(textLen: 0, source: "updateAutocompleteText")
            return
        }

        let layerCountBefore = overlayLayerCount()
        let reusedExistingLayer = inlineHostingView != nil && overlayWindow.contentView === inlineHostingView
        guard renderInlineGhostText(text, isStale: false) else {
            print("[RenderPipeline] skipped render because geometry unavailable")
            return
        }

        print("[TypeFlow-InputAudit] overlayWindowEvent=orderFront source=updateAutocompleteText visibleBefore=\(overlayWindow.isVisible) key=\(overlayWindow.isKeyWindow) main=\(overlayWindow.isMainWindow)")
        overlayWindow.orderFront(nil)
        let hasActiveCompletion = CompletionManager.shared.currentCompletion?.isEmpty == false
        CompletionManager.shared.accessibilityMonitor?.setAcceptTapNeededForVisibleCompletion(hasActiveCompletion, reason: "updateAutocompleteText-visible")

        lastRenderedAutocompleteText = text
        lastRenderedAutocompleteRequestID = requestID

        let layerCountAfter = overlayLayerCount()
        let durationMs = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
        let queueMs = (startedAt - requestedAt) * 1000
        print("[RenderPipeline] render applied requestID=\(requestID) textLen=\(text.count) durationMs=\(String(format: "%.1f", durationMs))")
        print("[RenderPipeline] reused existing text layer=\(reusedExistingLayer)")
        print("[RenderPipeline] layerCountBefore=\(layerCountBefore) layerCountAfter=\(layerCountAfter)")
        print("[RenderPipeline] renderMs=\(String(format: "%.1f", durationMs)) queueMs=\(String(format: "%.1f", queueMs))")
        LatencyInstrumentation.shared.renderApplied(textLen: text.count, source: "updateAutocompleteText")
    }

    @discardableResult
    private func renderInlineGhostText(_ text: String, isStale: Bool) -> Bool {
        guard !text.isEmpty else { return false }

        let geom: SuggestionOverlayGeometry
        if let existing = lastGeometry {
            geom = existing
        } else {
            guard lastCaretRect != .zero else { return false }
            let appKitCaretRect = appKitCaretRect(from: lastCaretRect)

            geom = SuggestionOverlayGeometry(
                caretRect: appKitCaretRect,
                inputFrameRect: nil,
                caretQuality: .exact,
                isCaretAtEndOfLine: true,
                observedCharWidth: nil,
                isRightToLeft: false,
                focusChangeSequence: focusSessionKey,
                focusedInputIdentityKey: focusSessionKey,
                isCorrection: completionModel.isSpellCorrection,
                resolvedFieldStyle: nil
            )
            lastGeometry = geom
        }

        let stabilizedCaretHeight = ghostFontStabilizer.stabilizedCaretHeight(
            geom.caretRect.height,
            focusSessionKey: geom.focusedInputIdentityKey
        )
        let referenceFieldFont = geom.resolvedFieldStyle.flatMap { fieldFont(from: $0) }
        let fontSize = lastInlineFontSize ?? resolvedGhostFontSize(
            forCaretHeight: stabilizedCaretHeight,
            caretQuality: geom.caretQuality,
            fieldFont: referenceFieldFont
        )
        let renderFont = lastInlineRenderFont ?? referenceFieldFont.flatMap { NSFont(name: $0.fontName, size: fontSize) }
        lastInlineFontSize = fontSize
        lastInlineRenderFont = renderFont

        let layout = GhostSuggestionLayout.make(
            text: text,
            geometry: geom,
            fontSize: fontSize,
            visibleFrame: targetScreenVisibleFrame(for: geom.caretRect),
            showsAcceptanceHint: false,
            font: renderFont
        )

        let rootView = GhostSuggestionView(
            layout: layout,
            fontSize: fontSize,
            fieldFont: renderFont,
            fieldColor: fieldGhostColor(from: geom.resolvedFieldStyle),
            customColor: nil,
            keycapLabel: nil,
            opacity: isStale ? 0.35 : 0.75,
            isCorrection: geom.isCorrection
        )

        if let inlineHostingView {
            inlineHostingView.rootView = rootView
        } else {
            inlineHostingView = NSHostingView(rootView: rootView)
        }

        if overlayWindow.contentView !== inlineHostingView {
            overlayWindow.contentView = inlineHostingView
        }
        overlayWindow.ignoresMouseEvents = true

        inlineHostingView?.layoutSubtreeIfNeeded()
        let contentSize = inlineHostingView?.fittingSize ?? .zero
        let frame = layout.panelFrame(for: contentSize, caretRect: geom.caretRect)
        guard AXHelper_rectHasFiniteComponents(frame) else { return false }

        overlayWindow.setFrame(frame.integral, display: true)
        logRenderReplace(text: text)
        return true
    }

    func replaceGhostTextAfterAcceptance(inserted: String, remainder: String, source: String = "tabAccept") {
        guard InputIsolationMode.current.allowOverlay else {
            print("[TypeFlow-InputIsolation] overlay/window mutation blocked mode=\(InputIsolationMode.current.label) action=replaceGhostTextAfterAcceptance")
            return
        }

        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.replaceGhostTextAfterAcceptance(inserted: inserted, remainder: remainder, source: source)
            }
            return
        }

        let mutation = PendingOverlayMutation.replaceGhostTextAfterAcceptance(inserted: inserted, remainder: remainder, source: source)
        guard !deferOverlayMutationIfNeeded(mutation, action: "replaceGhostTextAfterAcceptance") else { return }
        applyReplaceGhostTextAfterAcceptance(inserted: inserted, remainder: remainder, source: source)
    }

    private func applyReplaceGhostTextAfterAcceptance(inserted: String, remainder: String, source: String) {
        if source == "tabAccept" {
            print("[OverlayRender] tabAccept recomputeRemainderFromScratch inserted='\(inserted)' remainder='\(remainder)'")
        }

        let font = lastInlineRenderFont ?? NSFont.systemFont(ofSize: lastInlineFontSize ?? 13, weight: .regular)
        let attrs = [NSAttributedString.Key.font: font]
        let shiftPx = (inserted as NSString).size(withAttributes: attrs).width
        lastCaretRect.origin.x += shiftPx
        if let geom = lastGeometry {
            lastGeometry = geom.withCaretRect(geom.caretRect.offsetBy(dx: shiftPx, dy: 0))
        }

        if remainder.isEmpty {
            print("[OverlayRender] hideBecauseEmptyRemainder")
        }
        applyUpdateGhostText(remainder)
    }

    func updateGhostText(_ newText: String, isStale: Bool = false) {
        guard InputIsolationMode.current.allowOverlay else {
            print("[TypeFlow-InputIsolation] overlay/window mutation blocked mode=\(InputIsolationMode.current.label) action=updateGhostText")
            return
        }

        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.updateGhostText(newText, isStale: isStale)
            }
            return
        }

        let mutation = PendingOverlayMutation.updateGhostText(text: newText, isStale: isStale)
        guard !deferOverlayMutationIfNeeded(mutation, action: "updateGhostText") else { return }
        applyUpdateGhostText(newText, isStale: isStale)
    }

	    private func applyUpdateGhostText(_ newText: String, isStale: Bool = false) {
	        completionModel.text = newText
	        
	        guard !newText.isEmpty else {
	            clearAllRenderedGhostText(resetGeometry: true, clearPendingMutations: true)
            CompletionManager.shared.accessibilityMonitor?.setAcceptTapNeededForVisibleCompletion(false, reason: "updateGhostText-empty")
            print("[TypeFlow-InputAudit] overlayWindowEvent=orderOut source=updateGhostText visibleBefore=\(overlayWindow.isVisible) key=\(overlayWindow.isKeyWindow) main=\(overlayWindow.isMainWindow)")
            overlayWindow.orderOut(nil)
            return
        }

	        let hasActiveCompletion = CompletionManager.shared.currentCompletion?.isEmpty == false
	        CompletionManager.shared.accessibilityMonitor?.setAcceptTapNeededForVisibleCompletion(hasActiveCompletion && !isStale, reason: isStale ? "updateGhostText-stale" : "updateGhostText-active")

	        let before = overlayLayerCount()
	        if renderInlineGhostText(newText, isStale: isStale) {
	            print("[RenderPipeline] reused existing text layer=\(inlineHostingView != nil)")
	            print("[RenderPipeline] layerCountBefore=\(before) layerCountAfter=\(overlayLayerCount())")
	            LatencyInstrumentation.shared.renderApplied(textLen: newText.count, source: "updateGhostText")
	        } else {
	            print("[RenderPipeline] skipped render because geometry unavailable")
	        }
	    }

    func updateText(_ newText: String,
                    isSpellCorrection: Bool = false,
                    isRewrite: Bool = false,
                    isLoading: Bool = false,
                    isSmartReply: Bool = false,
                    smartReplyOptions: [String] = []) {
        guard InputIsolationMode.current.allowOverlay else {
            print("[TypeFlow-InputIsolation] overlay/window mutation blocked mode=\(InputIsolationMode.current.label) action=updateText")
            return
        }

        // Suppressed: print("[TypeFlow-Debug] OverlayWindowController updateText '\(newText.prefix(40))' ...")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let mutation = PendingOverlayMutation.updateText(
                text: newText,
                isSpellCorrection: isSpellCorrection,
                isRewrite: isRewrite,
                isLoading: isLoading,
                isSmartReply: isSmartReply,
                smartReplyOptions: smartReplyOptions
            )
            guard !self.deferOverlayMutationIfNeeded(mutation, action: "updateText") else { return }
            self.applyUpdateText(
                newText,
                isSpellCorrection: isSpellCorrection,
                isRewrite: isRewrite,
                isLoading: isLoading,
                isSmartReply: isSmartReply,
                smartReplyOptions: smartReplyOptions
            )
        }
    }

    private func applyUpdateText(_ newText: String,
                                 isSpellCorrection: Bool = false,
                                 isRewrite: Bool = false,
                                 isLoading: Bool = false,
                                 isSmartReply: Bool = false,
                                 smartReplyOptions: [String] = []) {
        completionModel.isSpellCorrection = isSpellCorrection
        completionModel.isRewrite = isRewrite
        completionModel.isLoading = isLoading
        completionModel.isSmartReply = isSmartReply
        completionModel.smartReplyOptions = smartReplyOptions
        completionModel.text = newText

        if newText.isEmpty && !isLoading && smartReplyOptions.isEmpty {
            clearAllRenderedGhostText(resetGeometry: true, clearPendingMutations: true)
            CompletionManager.shared.accessibilityMonitor?.setAcceptTapNeededForVisibleCompletion(false, reason: "updateText-empty")
            print("[TypeFlow-InputAudit] overlayWindowEvent=orderOut source=updateText visibleBefore=\(overlayWindow.isVisible) key=\(overlayWindow.isKeyWindow) main=\(overlayWindow.isMainWindow)")
            overlayWindow.orderOut(nil)
        } else {
            repositionWindow()
            print("[TypeFlow-InputAudit] overlayWindowEvent=orderFront source=updateText visibleBefore=\(overlayWindow.isVisible) key=\(overlayWindow.isKeyWindow) main=\(overlayWindow.isMainWindow)")
            overlayWindow.orderFront(nil)
            LatencyInstrumentation.shared.renderApplied(textLen: newText.count, source: "updateText")
            let hasActiveCompletion = CompletionManager.shared.currentCompletion?.isEmpty == false
            let shouldEnableAcceptTap = hasActiveCompletion && !newText.isEmpty && !isLoading && smartReplyOptions.isEmpty
            CompletionManager.shared.accessibilityMonitor?.setAcceptTapNeededForVisibleCompletion(shouldEnableAcceptTap, reason: "updateText-visible")
        }
    }

    // ─── Geometry and Style Resolution ────────────────────────────────────────

    private func resolveFieldStyle(for element: AXUIElement) -> ResolvedFieldStyle? {
        var selectedRangeRef: CFTypeRef?
        var caretLocation = 0
        var textLength = 1
        
        var valueRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success {
            if let str = valueRef as? String {
                textLength = str.count
            } else if let attrStr = valueRef as? NSAttributedString {
                textLength = attrStr.length
            }
        }
        
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRangeRef) == .success {
            let rangeValue = selectedRangeRef as! AXValue
            var range = CFRange(location: 0, length: 0)
            AXValueGetValue(rangeValue, .cfRange, &range)
            caretLocation = range.location
        }
        
        guard textLength > 0 else { return nil }
        let clampedCaret = min(max(caretLocation - 1, 0), textLength - 1)
        let candidateIndices = clampedCaret == 0 ? [0] : [clampedCaret, 0]
        
        for index in candidateIndices {
            var parameter: AXValue?
            var cfRange = CFRange(location: index, length: 1)
            parameter = AXValueCreate(.cfRange, &cfRange)
            
            if let parameter = parameter {
                var value: CFTypeRef?
                let result = AXUIElementCopyParameterizedAttributeValue(element, "AXAttributedStringForRange" as CFString, parameter, &value)
                if result == .success, let val = value as? NSAttributedString, val.length > 0 {
                    let attributes = val.attributes(at: 0, effectiveRange: nil)
                    var fontName: String?
                    var fontPointSize: CGFloat?
                    if let font = attributes[.font] as? NSFont {
                        fontName = font.fontName
                        fontPointSize = font.pointSize
                    } else if let fontInfo = attributes[NSAttributedString.Key("AXFont")] as? [String: Any] {
                        fontName = fontInfo["AXFontName"] as? String
                        if let size = fontInfo["AXFontSize"] as? NSNumber {
                            fontPointSize = CGFloat(size.doubleValue)
                        }
                    }
                    
                    var colorHex: String?
                    if let nsColor = attributes[.foregroundColor] as? NSColor {
                        colorHex = hexString(from: nsColor)
                    } else if let foreground = attributes[.foregroundColor],
                              CFGetTypeID(foreground as CFTypeRef) == CGColor.typeID {
                        let cgColor = foreground as! CGColor
                        if let nsColor = NSColor(cgColor: cgColor) {
                            colorHex = hexString(from: nsColor)
                        }
                    }
                    
                    let style = ResolvedFieldStyle(fontName: fontName, fontPointSize: fontPointSize, colorHex: colorHex)
                    if !style.isEmpty {
                        return style
                    }
                }
            }
        }
        return nil
    }
    
    private func hexString(from color: NSColor) -> String? {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        let r = Int(round(rgb.redComponent * 255))
        let g = Int(round(rgb.greenComponent * 255))
        let b = Int(round(rgb.blueComponent * 255))
        return String(format: "%02X%02X%02X", r, g, b)
    }

    private func fieldGhostColor(from style: ResolvedFieldStyle?) -> Color? {
        guard let hex = style?.colorHex,
              let nsColor = nsColor(fromHex: hex)?.usingColorSpace(.sRGB)
        else {
            return nil
        }

        let luminance = 0.299 * nsColor.redComponent
            + 0.587 * nsColor.greenComponent
            + 0.114 * nsColor.blueComponent
        guard luminance > 0.06, luminance < 0.94 else {
            return nil
        }

        return Color(nsColor: nsColor)
    }

    private func nsColor(fromHex hex: String) -> NSColor? {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int = UInt64()
        Scanner(string: cleaned).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch cleaned.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }
        return NSColor(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }

    private func fieldFont(from style: ResolvedFieldStyle) -> NSFont? {
        guard let name = style.fontName else { return nil }
        return NSFont(name: name, size: style.fontPointSize ?? 12)
    }

    private func resolvedGhostFontSize(
        forCaretHeight caretHeight: CGFloat,
        caretQuality: CaretGeometryQuality,
        fieldFont: NSFont?
    ) -> CGFloat {
        let qualityCap: CGFloat = caretQuality == .estimated ? 16 : 24
        
        let fieldMetrics = fieldFont.map {
            GhostFontMetrics.FieldFontMetrics(
                pointSize: $0.pointSize,
                ascender: $0.ascender,
                descender: $0.descender
            )
        }
        
        let heightToUse = caretHeight <= 0 ? 18 : caretHeight
        return GhostFontMetrics.pointSize(
            caretHeight: heightToUse,
            fieldMetrics: fieldMetrics,
            fallbackRatio: 0.78,
            minimum: 14,
            maximum: qualityCap,
            sizeMultiplier: 1.0
        )
    }

    private func targetScreenVisibleFrame(for caretRect: CGRect) -> CGRect {
        let midpoint = CGPoint(x: caretRect.midX, y: caretRect.midY)

        if let screen = NSScreen.screens.first(where: { $0.visibleFrame.contains(midpoint) }) {
            return screen.visibleFrame
        }

        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(caretRect) }) {
            return screen.visibleFrame
        }

        return NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 600)
    }

    private func AXHelper_rectHasFiniteComponents(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite
            && rect.size.width.isFinite && rect.size.height.isFinite
    }
}
