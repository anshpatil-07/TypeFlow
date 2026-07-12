import SwiftUI

// ─── Hotkey Recorder ─────────────────────────────────────────────────────────

/// A lightweight SwiftUI wrapper that records a key + modifier combination
/// and stores it as a display string like "⌥R" or "⌃⇧E".
struct HotkeyRecorderView: NSViewRepresentable {
    @Binding var shortcut: String

    func makeNSView(context: Context) -> HotkeyRecorderNSView {
        let v = HotkeyRecorderNSView()
        v.onShortcutRecorded = { [weak v] s in
            shortcut = s
            v?.isRecording = false
            v?.needsDisplay = true
        }
        return v
    }

    func updateNSView(_ nsView: HotkeyRecorderNSView, context: Context) {
        nsView.displayedShortcut = shortcut
        nsView.needsDisplay = true
    }
}

class HotkeyRecorderNSView: NSView {
    var displayedShortcut: String = ""
    var isRecording = false
    var onShortcutRecorded: ((String) -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override var focusRingType: NSFocusRingType {
        get { .exterior }
        set { }
    }

    override func draw(_ dirtyRect: NSRect) {
        let cornerRadius: CGFloat = 6
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1),
                                xRadius: cornerRadius, yRadius: cornerRadius)

        if isRecording {
            NSColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 0.15).setFill()
        } else {
            NSColor.controlBackgroundColor.setFill()
        }
        path.fill()

        let borderColor = isRecording
            ? NSColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 0.9)
            : NSColor.separatorColor
        borderColor.setStroke()
        path.lineWidth = isRecording ? 1.5 : 1.0
        path.stroke()

        let label = isRecording ? "Press shortcut…" : (displayedShortcut.isEmpty ? "Click to record" : displayedShortcut)
        let color: NSColor = isRecording ? NSColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 1) : .labelColor
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: color
        ]
        let str = NSAttributedString(string: label, attributes: attrs)
        let sz = str.size()
        str.draw(at: NSPoint(x: (bounds.width - sz.width) / 2, y: (bounds.height - sz.height) / 2))
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }

        // Escape cancels recording
        if event.keyCode == 53 {
            isRecording = false
            needsDisplay = true
            return
        }

        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !flags.isEmpty, let chars = event.charactersIgnoringModifiers?.uppercased(), !chars.isEmpty else {
            return // require at least one modifier
        }

        var parts: [String] = []
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option)  { parts.append("⌥") }
        if flags.contains(.shift)   { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        parts.append(chars)
        let shortcutString = parts.joined()
        onShortcutRecorded?(shortcutString)
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        needsDisplay = true
        return super.resignFirstResponder()
    }
}

// ─── Extracted Tab Views ────────────────────────────────────────────────────────

struct GeneralSettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @AppStorage("autoCorrectEnabled") private var autoCorrectEnabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            
            Text("Preferences")
                .font(.headline)
            
            Toggle("Enable Auto-Correct", isOn: $autoCorrectEnabled)
            
            Toggle("Use British English spelling", isOn: $settings.useBritishEnglish)
            
            Spacer()
        }
        .padding(40)
    }
}

struct ShortcutsSettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Accept Suggestion").font(.headline).foregroundColor(.primary)
                Picker("", selection: $settings.acceptShortcut) {
                    Text("Tab ⇥").tag("Tab")
                    Text("Right Arrow →").tag("Right Arrow")
                }
                .pickerStyle(SegmentedPickerStyle())
                .labelsHidden()
                Text("Press this key to accept a ghost-text suggestion inline.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Rewrite Selection").font(.headline).foregroundColor(.primary)
                HStack {
                    Text("Hotkey:")
                    HotkeyRecorderView(shortcut: $settings.rewriteShortcut)
                        .frame(width: 160, height: 34)
                        .help("Click then press your desired modifier + key combination. Press Esc to cancel.")
                    Button("Reset") {
                        settings.rewriteShortcut = "⌥R"
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .font(.caption)
                }
                Text("Select text in any app, then press this hotkey to trigger the AI Rewrite panel.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(40)
    }
}

struct ModelsSettingsView: View {
    @StateObject var modelManager = ModelManager()
    @ObservedObject var settings = SettingsManager.shared
    @State private var newModelId: String = ""
    @State private var infoPopoverModelId: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ─────────────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 4) {
                Text("AI Models")
                    .font(.title2).bold()
                Text("Only models rated ⚡ Instant or ✓ Good are suitable for TypeFlow's <150 ms real-time target.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 40)
            .padding(.top, 36)
            .padding(.bottom, 16)

            Divider()

            // ── Model list ─────────────────────────────────────────────────────
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(modelManager.models) { model in
                        modelRow(model)
                        Divider().opacity(0.5)
                    }
                }
                .padding(.horizontal, 40)
            }
            .frame(maxHeight: 320)

            Divider()

            // ── Custom model ───────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 10) {
                Text("Custom Model")
                    .font(.headline)
                Text("Paste an MLX Community Hugging Face Repo ID (e.g. mlx-community/SmolLM-135M-Instruct-4bit)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 10) {
                    TextField("Repo ID", text: $newModelId)
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                    Button("Download & Set Active") {
                        modelManager.addCustomModel(id: newModelId)
                        modelManager.activateModel(id: newModelId)
                        newModelId = ""
                    }
                    .disabled(newModelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 24)
        }
    }

    // MARK: - Model Row

    @ViewBuilder
    private func modelRow(_ model: MLXModel) -> some View {
        let isActive = settings.activeModelId == model.id
        let isBorderline = model.speedTier == .borderline

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {

                // ── Left: name + badges ────────────────────────────────────────
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(model.name)
                            .font(.body).bold()
                            .foregroundColor(isBorderline ? .secondary : .primary)

                        // Speed tier badge
                        Text(model.speedLabel)
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(model.speedColor.opacity(0.18))
                            .foregroundColor(model.speedColor)
                            .clipShape(Capsule())

                        // Info popover button
                        if model.description != nil {
                            Button {
                                infoPopoverModelId = (infoPopoverModelId == model.id) ? nil : model.id
                            } label: {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(BorderlessButtonStyle())
                            .popover(isPresented: Binding(
                                get: { infoPopoverModelId == model.id },
                                set: { if !$0 { infoPopoverModelId = nil } }
                            ), arrowEdge: .bottom) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(model.name).font(.headline)
                                    if let desc = model.description {
                                        Text(desc)
                                            .font(.body)
                                            .foregroundColor(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                .padding(14)
                                .frame(maxWidth: 260)
                            }
                        }
                    }

                    // Size label
                    if let size = model.sizeGB {
                        Text(String(format: "%.1f GB", size))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // ── Right: action buttons ──────────────────────────────────────
                HStack(spacing: 8) {
                    if isActive {
                        Label("Active", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.subheadline)
                    } else if model.status == .downloaded {
                        Button("Activate") {
                            modelManager.activateModel(id: model.id)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if model.status == .notDownloaded {
                        Button("Download") {
                            modelManager.downloadModel(id: model.id)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(isBorderline)   // discourage downloading slow models
                        .help(isBorderline ? "This model is too large for real-time autocomplete. Use at your own risk." : "")
                    }

                    if model.status == .downloaded && !isActive {
                        Button {
                            modelManager.deleteModel(id: model.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        .foregroundColor(.red)
                        .controlSize(.small)
                    }
                }
            }
            .padding(.vertical, 14)
            .opacity(isBorderline ? 0.65 : 1.0)

            // ── Full-width animated download progress bar ──────────────────────
            if model.status == .downloading {
                VStack(alignment: .trailing, spacing: 3) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.secondary.opacity(0.15))
                                .frame(height: 5)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * model.progress, height: 5)
                                .animation(.linear(duration: 0.2), value: model.progress)
                        }
                    }
                    .frame(height: 5)

                    HStack {
                        Text("Downloading…")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(model.progress * 100))%")
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.bottom, 10)
            }
        }
    }
}


// ─────────────────────────────────────────────────────────────────────────────
// Generation Tab View
// ─────────────────────────────────────────────────────────────────────────────
struct GenerationSettingsView: View {
    @AppStorage("globalTemperature") private var globalTemperature: Double = 0.2
    @AppStorage("globalMaxLength") private var globalMaxLength: Double = 20.0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            
            Text("Generation Settings")
                .font(.title2)
                .bold()
                .padding(.bottom, 8)
            
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("Temperature: \(String(format: "%.1f", globalTemperature))")
                        .font(.headline)
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                        .help("Controls the creativity and randomness of the generated text. Lower values are more predictable, higher values are more creative.")
                    Spacer()
                    Text(temperatureLabel(globalTemperature))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Slider(value: $globalTemperature, in: 0.0...1.0, step: 0.1)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("Max Length (tokens): \(Int(globalMaxLength))")
                        .font(.headline)
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                        .help("Limits the maximum number of tokens (words/pieces of words) the AI can generate in a single response.")
                }
                Slider(value: $globalMaxLength, in: 5...50, step: 1)
            }
            
            Spacer()
        }
        .padding(40)
        .frame(minWidth: 500, minHeight: 400)
    }
    
    private func temperatureLabel(_ temp: Double) -> String {
        if temp < 0.2 { return "Very Focused" }
        if temp < 0.5 { return "Balanced" }
        if temp < 0.8 { return "Creative" }
        return "Very Creative"
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Snippets Tab View
// ─────────────────────────────────────────────────────────────────────────────
struct SnippetsSettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @State private var newShortcut: String = ""
    @State private var newReplacement: String = ""
    
    var body: some View {
        VStack {
            List {
                Section(header: Text("My Snippets")) {
                    ForEach(Array(settings.getSnippets().keys.sorted()), id: \.self) { key in
                        HStack {
                            Text(key)
                                .font(.system(.body, design: .monospaced))
                                .bold()
                                .frame(width: 120, alignment: .leading)
                            
                            Image(systemName: "arrow.right")
                                .foregroundColor(.secondary)
                            
                            Text(settings.getSnippets()[key] ?? "")
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Button(action: { deleteSnippet(key) }) {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                    }
                }
                
                let suggestions = TypingHistoryManager.shared.getSuggestedSnippets()
                if !suggestions.isEmpty {
                    Section(header: Text("Suggested Snippets (From History)")) {
                        ForEach(0..<suggestions.count, id: \.self) { index in
                            let suggestion = suggestions[index]
                            SuggestedSnippetRow(suggestion: suggestion, settings: settings)
                        }
                    }
                }
            }
            
            HStack {
                TextField("Shortcut (e.g. /email)", text: $newShortcut)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                TextField("Replacement text", text: $newReplacement)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Button("Add") {
                    addSnippet()
                }
                .disabled(newShortcut.isEmpty || newReplacement.isEmpty)
            }
            .padding(40)
        }
    }
    
    private func addSnippet() {
        var snippets = settings.getSnippets()
        snippets[newShortcut] = newReplacement
        settings.saveSnippets(snippets)
        newShortcut = ""
        newReplacement = ""
    }
    
    private func deleteSnippet(_ key: String) {
        var snippets = settings.getSnippets()
        snippets.removeValue(forKey: key)
        settings.saveSnippets(snippets)
    }
}

struct SuggestedSnippetRow: View {
    let suggestion: (text: String, suggestedShortcode: String)
    @ObservedObject var settings: SettingsManager
    @State private var customizedShortcode: String
    
    init(suggestion: (text: String, suggestedShortcode: String), settings: SettingsManager) {
        self.suggestion = suggestion
        self.settings = settings
        self._customizedShortcode = State(initialValue: suggestion.suggestedShortcode)
    }
    
    var body: some View {
        HStack {
            TextField("Shortcode", text: $customizedShortcode)
                .font(.system(.body, design: .monospaced))
                .frame(width: 120)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            Image(systemName: "arrow.right")
                .foregroundColor(.secondary)
            
            Text(suggestion.text)
                .foregroundColor(.secondary)
                .lineLimit(1)
            
            Spacer()
            
            Button("Add") {
                var snippets = settings.getSnippets()
                snippets[customizedShortcode] = suggestion.text
                settings.saveSnippets(snippets)
            }
            .buttonStyle(BorderlessButtonStyle())
        }
    }
}

