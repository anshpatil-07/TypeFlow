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
        
        DispatchQueue.main.async {
            CompletionManager.shared.cancelInflightTasks()
            CompletionManager.shared.hideOverlay()
            CompletionManager.shared.clearCompletion()
            CompletionManager.shared.accessibilityMonitor?.clearKeystrokeBuffer()
        }
        
        UniversalContextManager.shared.refreshContext()
        ScreenContextManager.shared.performOCROnDemand()
        
        let config = SettingsManager.shared.getEffectiveConfig(for: bundleId)
        if config.isEnabled {
            LLMEngine.shared.prewarmCache(toneProfile: config.toneProfile)
        }
        
        checkAndEnableBrowserAccessibility(for: app.processIdentifier)
    }
    
    private func checkAndEnableBrowserAccessibility(for pid: pid_t) {
        let appElement = AXUIElementCreateApplication(pid)
        
        var mainRole: CFTypeRef?
        AXUIElementCopyAttributeValue(appElement, kAXRoleAttribute as CFString, &mainRole)
        
        // Browsers often have AXWebArea children or their main document is an HTML document.
        // For simplicity, we just enable it for any app that might need enhanced UI.
        enableBrowserAccessibility(for: pid)
    }
    
    private func enableBrowserAccessibility(for pid: pid_t) {
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 1.0)
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        print("[TypeFlow-Debug] AppMonitor: Enabled enhanced accessibility for browser PID \(pid)")
    }
}
