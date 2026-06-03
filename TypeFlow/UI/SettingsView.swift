import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @StateObject var modelManager = ModelManager()
    
    var body: some View {
        TabView {
            // General Tab
            Form {
                Picker("Accept Shortcut:", selection: $settings.acceptShortcut) {
                    Text("Tab").tag("Tab")
                    Text("Right Arrow").tag("Right Arrow")
                }
                .pickerStyle(SegmentedPickerStyle())
                
                Picker("Completion Tone:", selection: $settings.tone) {
                    ForEach(settings.getTones()) { tone in
                        Text(tone.name).tag(tone.id)
                    }
                }
                .padding(.top)
                
                Toggle("Auto-correct misspelled words as you type", isOn: $settings.autoCorrectEnabled)
                    .padding(.top)
                
                Toggle("Enable personalization (Typing History)", isOn: $settings.personalizationEnabled)
                    .padding(.top)
            }
            .padding()
            .tabItem {
                Label("General", systemImage: "gear")
            }
            
            // Models Tab
            Form {
                ForEach(modelManager.models) { model in
                    HStack {
                        Text(model.name)
                            .font(.headline)
                        
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
                            ProgressView(value: model.progress)
                                .frame(width: 100)
                            Text("\(Int(model.progress * 100))%")
                                .font(.caption)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding()
            .tabItem {
                Label("Models", systemImage: "cpu")
            }
            
            // Tones Tab (Replaces Persona Tab)
            TonesSettingsView()
                .tabItem {
                    Label("Tones", systemImage: "person.text.rectangle")
                }
            
            // Snippets Tab
            SnippetsSettingsView()
                .tabItem {
                    Label("Snippets", systemImage: "text.badge.plus")
                }
            
            // Apps Tab
            AppOverridesSettingsView()
                .tabItem {
                    Label("Apps", systemImage: "app.badge")
                }
        }
        .frame(width: 600, height: 450)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tones Tab View
// ─────────────────────────────────────────────────────────────────────────────
struct TonesSettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @State private var selectedToneId: String = "Neutral"
    
    var body: some View {
        HStack(spacing: 0) {
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
            .frame(width: 180)
            
            Divider()
            
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
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack {
                    Text("Select a tone to edit or view details.")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            
            HStack {
                TextField("Shortcut", text: $newShortcut)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                TextField("Replacement", text: $newReplacement)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Button("Add") {
                    addSnippet()
                }
                .disabled(newShortcut.isEmpty || newReplacement.isEmpty)
            }
            .padding()
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

// ─────────────────────────────────────────────────────────────────────────────
// App Overrides Tab View
// ─────────────────────────────────────────────────────────────────────────────
struct AppOverridesSettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @State private var newBundleId: String = ""
    @State private var selectedBundleId: String = ""
    
    var body: some View {
        HStack(spacing: 0) {
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
            .frame(width: 180)
            
            Divider()
            
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
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack {
                    Text("Select or add an App Bundle ID to configure overrides.")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
