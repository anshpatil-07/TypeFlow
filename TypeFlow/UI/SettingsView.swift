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
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Picker("Completion Tone:", selection: $settings.tone) {
                ForEach(settings.getTones()) { tone in
                    Text(tone.name).tag(tone.id)
                }
            }
            .pickerStyle(MenuPickerStyle())

            Toggle("Auto-correct misspelled words as you type", isOn: $settings.autoCorrectEnabled)

            Toggle("Enable personalization (Typing History)", isOn: $settings.personalizationEnabled)

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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Recommended Models")
                .font(.headline)
            
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(modelManager.models) { model in
                        HStack {
                            Text(model.name)
                                .font(.body)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            
                            Spacer()
                            
                            if settings.activeModelId == model.id {
                                Text("Active")
                                    .foregroundColor(.green)
                                    .font(.subheadline)
                                    .padding(.trailing, 8)
                            } else if model.status == .downloaded {
                                Button("Activate") {
                                    modelManager.activateModel(id: model.id)
                                }
                            }
                            
                            if model.status == .notDownloaded {
                                Button("Download") {
                                    modelManager.downloadModel(id: model.id)
                                }
                            } else if model.status == .downloading {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(.horizontal, 4)
                                Text("Downloading...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            if model.status == .downloaded && settings.activeModelId != model.id {
                                Button(action: { modelManager.deleteModel(id: model.id) }) {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(BorderlessButtonStyle())
                                .foregroundColor(.red)
                                .padding(.leading, 4)
                            }
                        }
                        .padding(.vertical, 8)
                        
                        Divider()
                    }
                }
            }
            .frame(maxHeight: 250)
            
            Spacer()
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Custom Model")
                    .font(.headline)
                Text("Paste an MLX Community Hugging Face Repo ID (e.g. mlx-community/SmolLM-135M-Instruct-4bit)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
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
        }
        .padding(40)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tones Tab View
// ─────────────────────────────────────────────────────────────────────────────
struct TonesSettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @State private var selectedToneId: String = "Neutral"
    
    var body: some View {
        NavigationSplitView {
            // Sidebar List of Tone Profiles
            VStack(spacing: 0) {
                List(selection: $selectedToneId) {
                    Section(header: Text("Built-in")) {
                        ForEach(SettingsManager.builtInTones) { tone in
                            Text(tone.name).tag(tone.id)
                        }
                    }
                    Section(header: Text("Custom")) {
                        ForEach(settings.getCustomTones()) { tone in
                            Text(tone.name).tag(tone.id)
                        }
                    }
                }
                .listStyle(SidebarListStyle())
                
                HStack {
                    Button(action: addCustomTone) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(BorderedButtonStyle())
                    
                    Button(action: deleteSelectedCustomTone) {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(BorderedButtonStyle())
                    .disabled(isBuiltIn(selectedToneId))
                    
                    Spacer()
                    
                    Button("Duplicate") {
                        duplicateTone()
                    }
                    .buttonStyle(BorderedButtonStyle())
                }
                .padding(8)
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 200)
        } detail: {
            // Editor Panel on Right
            if let tone = getTone(by: selectedToneId) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(tone.isBuiltIn ? "Built-in Tone Profile (Read-only)" : "Custom Tone Profile")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if tone.isBuiltIn {
                        Text(tone.name)
                            .font(.title2)
                            .bold()
                            .padding(.bottom, 4)
                    } else {
                        TextField("Name", text: nameBinding(for: tone.id))
                            .font(.title2)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .padding(.bottom, 4)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Instructions:")
                            .font(.subheadline)
                            .bold()
                        TextEditor(text: instructionsBinding(for: tone.id))
                            .frame(height: 100)
                            .cornerRadius(4)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.3)))
                            .disabled(tone.isBuiltIn)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Temperature: \(String(format: "%.1f", tone.temperature))")
                                .font(.subheadline)
                                .bold()
                            Spacer()
                            Text(temperatureLabel(tone.temperature))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Slider(value: temperatureBinding(for: tone.id), in: 0.0...1.0, step: 0.1)
                            .disabled(tone.isBuiltIn)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Max Length (tokens): \(tone.maxTokens)")
                            .font(.subheadline)
                            .bold()
                        Slider(value: maxTokensBinding(for: tone.id), in: 5...50, step: 1)
                            .disabled(tone.isBuiltIn)
                    }
                    
                    Spacer()
                }
                .padding(40)
                .frame(minWidth: 350, maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack {
                    Text("Select a tone to edit or view details.")
                        .foregroundColor(.secondary)
                }
                .frame(minWidth: 350, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    private func isBuiltIn(_ id: String) -> Bool {
        return SettingsManager.builtInTones.contains(where: { $0.id == id })
    }
    
    private func getTone(by id: String) -> ToneProfile? {
        return settings.getToneProfile(by: id)
    }
    
    private func nameBinding(for id: String) -> Binding<String> {
        Binding(
            get: { getTone(by: id)?.name ?? "" },
            set: { newValue in
                var customs = settings.getCustomTones()
                if let index = customs.firstIndex(where: { $0.id == id }) {
                    customs[index].name = newValue
                    settings.saveCustomTones(customs)
                }
            }
        )
    }
    
    private func instructionsBinding(for id: String) -> Binding<String> {
        Binding(
            get: { getTone(by: id)?.systemInstructions ?? "" },
            set: { newValue in
                var customs = settings.getCustomTones()
                if let index = customs.firstIndex(where: { $0.id == id }) {
                    customs[index].systemInstructions = newValue
                    settings.saveCustomTones(customs)
                }
            }
        )
    }
    
    private func temperatureBinding(for id: String) -> Binding<Double> {
        Binding(
            get: { getTone(by: id)?.temperature ?? 0.2 },
            set: { newValue in
                var customs = settings.getCustomTones()
                if let index = customs.firstIndex(where: { $0.id == id }) {
                    customs[index].temperature = newValue
                    settings.saveCustomTones(customs)
                }
            }
        )
    }
    
    private func maxTokensBinding(for id: String) -> Binding<Double> {
        Binding(
            get: { Double(getTone(by: id)?.maxTokens ?? 20) },
            set: { newValue in
                var customs = settings.getCustomTones()
                if let index = customs.firstIndex(where: { $0.id == id }) {
                    customs[index].maxTokens = Int(newValue)
                    settings.saveCustomTones(customs)
                }
            }
        )
    }
    
    private func temperatureLabel(_ temp: Double) -> String {
        if temp < 0.2 { return "Very Focused" }
        if temp < 0.5 { return "Balanced" }
        if temp < 0.8 { return "Creative" }
        return "Very Creative"
    }
    
    private func addCustomTone() {
        let newId = UUID().uuidString
        let newTone = ToneProfile(
            id: newId,
            name: "Custom Tone",
            systemInstructions: "Complete the text.",
            temperature: 0.2,
            maxTokens: 20,
            isBuiltIn: false
        )
        var customs = settings.getCustomTones()
        customs.append(newTone)
        settings.saveCustomTones(customs)
        selectedToneId = newId
    }
    
    private func deleteSelectedCustomTone() {
        var customs = settings.getCustomTones()
        customs.removeAll(where: { $0.id == selectedToneId })
        settings.saveCustomTones(customs)
        selectedToneId = "Neutral"
    }
    
    private func duplicateTone() {
        guard let baseTone = getTone(by: selectedToneId) else { return }
        let newId = UUID().uuidString
        let newTone = ToneProfile(
            id: newId,
            name: "\(baseTone.name) Copy",
            systemInstructions: baseTone.systemInstructions,
            temperature: baseTone.temperature,
            maxTokens: baseTone.maxTokens,
            isBuiltIn: false
        )
        var customs = settings.getCustomTones()
        customs.append(newTone)
        settings.saveCustomTones(customs)
        selectedToneId = newId
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

// ─────────────────────────────────────────────────────────────────────────────
// App Overrides Tab View
// ─────────────────────────────────────────────────────────────────────────────
struct AppOverridesSettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @State private var newBundleId: String = ""
    @State private var selectedBundleId: String = ""
    
    var body: some View {
        NavigationSplitView {
            // Sidebar List of App Overrides
            VStack(spacing: 0) {
                List(selection: $selectedBundleId) {
                    ForEach(Array(settings.getAppConfigs().keys.sorted()), id: \.self) { bundleId in
                        Text(bundleId).tag(bundleId)
                    }
                }
                .listStyle(SidebarListStyle())
                
                HStack {
                    TextField("Bundle ID", text: $newBundleId)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Button(action: addAppOverride) {
                        Image(systemName: "plus")
                    }
                    .disabled(newBundleId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    
                    Button(action: deleteSelectedAppOverride) {
                        Image(systemName: "minus")
                    }
                    .disabled(selectedBundleId.isEmpty)
                }
                .padding(8)
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 200)
        } detail: {
            // Detail Editor
            if !selectedBundleId.isEmpty, let config = settings.getAppConfigs()[selectedBundleId] {
                VStack(alignment: .leading, spacing: 12) {
                    Text("App Override: \(selectedBundleId)")
                        .font(.headline)
                    
                    Toggle("Enable Autocomplete for this app", isOn: bindingForEnabled(selectedBundleId))
                        .padding(.bottom, 8)
                    
                    if config.isEnabled {
                        Picker("App Tone Profile:", selection: bindingForTone(selectedBundleId)) {
                            ForEach(settings.getTones()) { tone in
                                Text(tone.name).tag(tone.id)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("App Custom Instructions (Optional):")
                                .font(.subheadline)
                                .bold()
                            TextEditor(text: bindingForInstructions(selectedBundleId))
                                .frame(height: 100)
                                .cornerRadius(4)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.3)))
                        }
                    }
                    
                    Spacer()
                }
                .padding(40)
                .frame(minWidth: 350, maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack {
                    Text("Select or add an App Bundle ID to configure overrides.")
                        .foregroundColor(.secondary)
                }
                .frame(minWidth: 350, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    private func addAppOverride() {
        let cleanId = newBundleId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanId.isEmpty else { return }
        var configs = settings.getAppConfigs()
        if configs[cleanId] == nil {
            configs[cleanId] = AppConfig(isEnabled: true, customTone: "Neutral", customInstructions: "")
            settings.saveAppConfigs(configs)
        }
        selectedBundleId = cleanId
        newBundleId = ""
    }
    
    private func deleteSelectedAppOverride() {
        guard !selectedBundleId.isEmpty else { return }
        var configs = settings.getAppConfigs()
        configs.removeValue(forKey: selectedBundleId)
        settings.saveAppConfigs(configs)
        selectedBundleId = ""
    }
    
    private func bindingForEnabled(_ bundleId: String) -> Binding<Bool> {
        Binding(
            get: { settings.getAppConfigs()[bundleId]?.isEnabled ?? true },
            set: { newValue in
                var configs = settings.getAppConfigs()
                configs[bundleId]?.isEnabled = newValue
                settings.saveAppConfigs(configs)
            }
        )
    }
    
    private func bindingForTone(_ bundleId: String) -> Binding<String> {
        Binding(
            get: { settings.getAppConfigs()[bundleId]?.customTone ?? "Neutral" },
            set: { newValue in
                var configs = settings.getAppConfigs()
                configs[bundleId]?.customTone = newValue
                settings.saveAppConfigs(configs)
            }
        )
    }
    
    private func bindingForInstructions(_ bundleId: String) -> Binding<String> {
        Binding(
            get: { settings.getAppConfigs()[bundleId]?.customInstructions ?? "" },
            set: { newValue in
                var configs = settings.getAppConfigs()
                configs[bundleId]?.customInstructions = newValue
                settings.saveAppConfigs(configs)
            }
        )
    }
}
