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
    
    @AppStorage("customTonesData") var customTonesData: Data = Data()
    
    private init() {}
    
    static let builtInTones: [ToneProfile] = [
        ToneProfile(id: "Neutral", name: "Neutral", systemInstructions: "Complete the text. Output only the next few words. No explanation.", temperature: 0.2, maxTokens: 20, isBuiltIn: true),
        ToneProfile(id: "Professional", name: "Professional", systemInstructions: "Complete the text in a professional, formal, and polite tone. Output only the next few words. No explanation.", temperature: 0.1, maxTokens: 20, isBuiltIn: true),
        ToneProfile(id: "Casual", name: "Casual", systemInstructions: "Complete the text in a friendly, casual, and conversational tone. Output only the next few words. No explanation.", temperature: 0.4, maxTokens: 25, isBuiltIn: true),
        ToneProfile(id: "Concise", name: "Concise", systemInstructions: "Complete the text extremely concisely. Output only the next one or two words. No explanation.", temperature: 0.0, maxTokens: 10, isBuiltIn: true)
    ]
    
    func getCustomTones() -> [ToneProfile] {
        if let decoded = try? JSONDecoder().decode([ToneProfile].self, from: customTonesData) {
            return decoded
        }
        return []
    }
    
    func saveCustomTones(_ tones: [ToneProfile]) {
        if let encoded = try? JSONEncoder().encode(tones) {
            customTonesData = encoded
        }
    }
    
    func getTones() -> [ToneProfile] {
        var list = Self.builtInTones
        list.append(contentsOf: getCustomTones())
        return list
    }
    
    func getToneProfile(by id: String) -> ToneProfile {
        return getTones().first { $0.id == id } ?? Self.builtInTones[0]
    }
    
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
    
    func getEffectiveConfig(for bundleId: String) -> (isEnabled: Bool, toneProfile: ToneProfile) {
        let configs = getAppConfigs()
        
        // Check old excluded list for backwards compatibility
        let excludedList = excludedApps.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            
        if excludedList.contains(bundleId) {
            return (false, getToneProfile(by: tone))
        }
        
        if let specificConfig = configs[bundleId] {
            let activeToneId = specificConfig.customTone ?? tone
            var profile = getToneProfile(by: activeToneId)
            if let customInst = specificConfig.customInstructions, !customInst.isEmpty {
                profile.systemInstructions = customInst
            }
            return (specificConfig.isEnabled, profile)
        }
        
        return (true, getToneProfile(by: tone))
    }
}

struct AppConfig: Codable, Equatable {
    var isEnabled: Bool
    var customTone: String?
    var customInstructions: String?
}

struct ToneProfile: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var systemInstructions: String
    var temperature: Double
    var maxTokens: Int
    var isBuiltIn: Bool
}
