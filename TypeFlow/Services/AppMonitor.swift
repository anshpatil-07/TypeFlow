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
        
        let lowerBundleId = bundleId.lowercased()
        if lowerBundleId.contains("chrome") || lowerBundleId.contains("safari") || lowerBundleId.contains("zen") || lowerBundleId.contains("firefox") || lowerBundleId.contains("edge") || lowerBundleId.contains("brave") {
            enableBrowserAccessibility(for: app.processIdentifier)
        }
    }
    
    private func enableBrowserAccessibility(for pid: pid_t) {
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 1.0)
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        print("[TypeFlow-Debug] AppMonitor: Enabled enhanced accessibility for browser PID \(pid)")
    }
}
