import SwiftUI
import Combine
import CryptoKit

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    @AppStorage("customInstructions") var customInstructions: String = ""
    @AppStorage("acceptShortcut") var acceptShortcut: String = "Tab"
    @AppStorage("rewriteShortcut") var rewriteShortcut: String = "Option+R"
    @AppStorage("smartReplyShortcut") var smartReplyShortcut: String = "Command+Shift+R"
    @AppStorage("excludedApps") var excludedApps: String = "com.agilebits.onepassword7,com.apple.keychainaccess"
    @AppStorage("autoCorrectEnabled") var autoCorrectEnabled: Bool = false
    @AppStorage("personalizationEnabled") var personalizationEnabled: Bool = false
    @AppStorage("enableAutocomplete") var enableAutocomplete: Bool = true
    @AppStorage("useBritishEnglish") var useBritishEnglish: Bool = false
    
    @AppStorage("tone") var tone: String = "Neutral"
    @AppStorage("snippetsData") var snippetsData: Data = Data()

    // @AppStorage("activeModelId") var activeModelId: String = "mlx-community/gemma-4-E4B-it-4bit"
    var activeModelId: String {
        get { "mlx-community/gemma-4-E4B-it-4bit" }
        set { /* Locked for beta release */ }
    }
    
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
    
    private func getSymmetricKey() -> SymmetricKey? {
        let keyName = "com.cotyper.TypeFlow.historyKey"
        if let keyData = KeychainHelper.load(key: keyName) {
            return SymmetricKey(data: keyData)
        }
        let newKey = SymmetricKey(size: .bits256)
        let newKeyData = newKey.withUnsafeBytes { Data($0) }
        _ = KeychainHelper.save(key: keyName, data: newKeyData)
        return newKey
    }
    
    private var snippetsFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let typeFlowDir = appSupport.appendingPathComponent("TypeFlow")
        try? FileManager.default.createDirectory(at: typeFlowDir, withIntermediateDirectories: true)
        return typeFlowDir.appendingPathComponent("snippets.enc")
    }
    
    func getSnippets() -> [String: String] {
        // First check for migration
        if !snippetsData.isEmpty {
            if let decoded = try? JSONDecoder().decode([String: String].self, from: snippetsData) {
                print("[TypeFlow-Debug] SettingsManager: Migrating unencrypted snippets from UserDefaults...")
                saveSnippets(decoded)
                snippetsData = Data() // Clear plaintext setting
                return decoded
            }
        }
        
        guard let key = getSymmetricKey() else {
            print("[TypeFlow-Debug] SettingsManager: getSnippets failed - symmetricKey is nil")
            return [:]
        }
        
        do {
            let encryptedData = try Data(contentsOf: snippetsFileURL)
            let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
            let decryptedData = try AES.GCM.open(sealedBox, using: key)
            let decoded = try JSONDecoder().decode([String: String].self, from: decryptedData)
            return decoded
        } catch {
            return [:]
        }
    }
    
    func saveSnippets(_ snippets: [String: String]) {
        guard let key = getSymmetricKey() else {
            print("[TypeFlow-Debug] SettingsManager: saveSnippets failed - symmetricKey is nil")
            return
        }
        
        do {
            let data = try JSONEncoder().encode(snippets)
            let sealedBox = try AES.GCM.seal(data, using: key)
            try sealedBox.combined?.write(to: snippetsFileURL)
            print("[TypeFlow-Debug] SettingsManager: Saved \(snippets.count) snippets to disk (encrypted)")
        } catch {
            print("[TypeFlow-Debug] SettingsManager: ERROR saving snippets: \(error)")
        }
    }
    
    func getEffectiveConfig(for bundleId: String) -> (isEnabled: Bool, toneProfile: ToneProfile) {
        // Check old excluded list for backwards compatibility
        let excludedList = excludedApps.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            
        if excludedList.contains(bundleId) {
            return (false, getToneProfile(by: tone))
        }
        
        return (true, getToneProfile(by: tone))
    }
}

struct ToneProfile: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var systemInstructions: String
    var temperature: Double
    var maxTokens: Int
    var isBuiltIn: Bool
}
