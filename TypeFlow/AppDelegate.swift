import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var menuBarManager: MenuBarManager?
    var accessibilityMonitor: AccessibilityMonitor?
    var overlayWindowController: OverlayWindowController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        menuBarManager = MenuBarManager()
        overlayWindowController = OverlayWindowController()
        
        accessibilityMonitor = AccessibilityMonitor { [weak self] rect in
            self?.overlayWindowController?.moveOverlay(to: rect)
        }
        
        if let monitor = accessibilityMonitor, let overlay = overlayWindowController {
            CompletionManager.shared.setup(accessibilityMonitor: monitor, overlayWindowController: overlay)
        }
        
        // Delay start by 1 second: AXIsProcessTrusted() can return false immediately
        // on launch even when permission IS already granted in System Settings,
        // because the sandbox trust status hasn't propagated yet.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.accessibilityMonitor?.startWithRetry()
        }
    }
}
