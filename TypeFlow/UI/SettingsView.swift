import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    
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
