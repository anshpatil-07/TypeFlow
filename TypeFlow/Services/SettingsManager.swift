import SwiftUI
import Combine

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    @AppStorage("customInstructions") var customInstructions: String = ""
    @AppStorage("acceptShortcut") var acceptShortcut: String = "Tab"
    @AppStorage("excludedApps") var excludedApps: String = "com.agilebits.onepassword7,com.apple.keychainaccess"
    @AppStorage("autoCorrectEnabled") var autoCorrectEnabled: Bool = false
    @AppStorage("personalizationEnabled") var personalizationEnabled: Bool = false
    
    @AppStorage("tone") var tone: String = "Neutral"
    @AppStorage("snippetsData") var snippetsData: Data = Data()
    @AppStorage("appConfigsData") var appConfigsData: Data = Data()
    @AppStorage("activeModelId") var activeModelId: String = "gemma-3-4b-it-qat-4bit"
    
    private init() {}
    
    func isAppExcluded(bundleId: String) -> Bool {
        return !getEffectiveConfig(for: bundleId).isEnabled
    }
    
    func getSnippets() -> [String: String] {
        if let decoded = try? JSONDecoder().decode([String: String].self, from: snippetsData) {
            return decoded
        }
        return [:]
    }
    
    func saveSnippets(_ snippets: [String: String]) {
        if let encoded = try? JSONEncoder().encode(snippets) {
            snippetsData = encoded
        }
    }
    
    func getAppConfigs() -> [String: AppConfig] {
        if let decoded = try? JSONDecoder().decode([String: AppConfig].self, from: appConfigsData) {
            return decoded
        }
        return [:]
    }
    
    func saveAppConfigs(_ configs: [String: AppConfig]) {
        if let encoded = try? JSONEncoder().encode(configs) {
            appConfigsData = encoded
        }
    }
    
    func getEffectiveConfig(for bundleId: String) -> (isEnabled: Bool, tone: String, instructions: String) {
        let configs = getAppConfigs()
        
        // Check old excluded list for backwards compatibility
        let excludedList = excludedApps.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            
        if excludedList.contains(bundleId) {
            return (false, tone, customInstructions)
        }
        
        if let specificConfig = configs[bundleId] {
            return (
                specificConfig.isEnabled,
                specificConfig.customTone ?? tone,
                specificConfig.customInstructions ?? customInstructions
            )
        }
        
        return (true, tone, customInstructions)
    }
}

struct AppConfig: Codable, Equatable {
    var isEnabled: Bool
    var customTone: String?
    var customInstructions: String?
}
