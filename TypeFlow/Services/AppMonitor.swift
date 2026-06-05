import Foundation
import AppKit

class AppMonitor {
    static let shared = AppMonitor()
    
    private init() {}
    
    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        print("[TypeFlow-Debug] AppMonitor started listening for app switches.")
    }
    
    @objc private func appActivated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleId = app.bundleIdentifier else { return }
        
        print("[TypeFlow-Debug] AppMonitor: Activated app '\(bundleId)'")
        
        let config = SettingsManager.shared.getEffectiveConfig(for: bundleId)
        if config.isEnabled {
            LLMEngine.shared.prewarmCache(toneProfile: config.toneProfile)
        }
    }
}
