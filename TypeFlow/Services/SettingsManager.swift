import SwiftUI
import Combine

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    @AppStorage("customInstructions") var customInstructions: String = ""
    @AppStorage("acceptShortcut") var acceptShortcut: String = "Tab"
    @AppStorage("excludedApps") var excludedApps: String = "com.agilebits.onepassword7,com.apple.keychainaccess"
    
    private init() {}
    
    func isAppExcluded(bundleId: String) -> Bool {
        let excludedList = excludedApps.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        return excludedList.contains(bundleId)
    }
}
