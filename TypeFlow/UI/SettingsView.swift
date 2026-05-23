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
                    Text("Neutral").tag("Neutral")
                    Text("Professional").tag("Professional")
                    Text("Casual").tag("Casual")
                    Text("Concise").tag("Concise")
                }
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
            
            // Persona Tab
            Form {
                VStack(alignment: .leading) {
                    Text("Custom Instructions / Persona:")
                        .font(.headline)
                    Text("Add your own instructions to guide the LLM's completions.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextEditor(text: $settings.customInstructions)
                        .frame(height: 150)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.5)))
                }
            }
            .padding()
            .tabItem {
                Label("Persona", systemImage: "person.text.rectangle")
            }
            
            // Snippets Tab
            Form {
                Text("Snippets UI Placeholder")
                // A complete list/add/remove UI would go here, updating SettingsManager.shared.saveSnippets()
            }
            .padding()
            .tabItem {
                Label("Snippets", systemImage: "text.badge.plus")
            }
            
            // Apps Tab
            Form {
                Text("App Overrides UI Placeholder")
                // A complete list/add/remove UI would go here, updating SettingsManager.shared.saveAppConfigs()
            }
            .padding()
            .tabItem {
                Label("Apps", systemImage: "app.badge")
            }
        }
        .frame(width: 500, height: 350)
    }
}
