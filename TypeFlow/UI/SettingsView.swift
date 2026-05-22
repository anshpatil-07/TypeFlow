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
                
                VStack(alignment: .leading) {
                    Text("Excluded Apps (Bundle Identifiers, comma separated):")
                    TextEditor(text: $settings.excludedApps)
                        .frame(height: 100)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.5)))
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
        }
        .frame(width: 450, height: 300)
    }
}
