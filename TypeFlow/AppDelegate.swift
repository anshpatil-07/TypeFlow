import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var menuBarManager: MenuBarManager?
    var accessibilityMonitor: AccessibilityMonitor?
    var overlayWindowController: OverlayWindowController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarManager = MenuBarManager()
        overlayWindowController = OverlayWindowController()
        
        accessibilityMonitor = AccessibilityMonitor { [weak self] rect in
            self?.overlayWindowController?.moveOverlay(to: rect)
        }
        
        if let monitor = accessibilityMonitor, let overlay = overlayWindowController {
            CompletionManager.shared.setup(accessibilityMonitor: monitor, overlayWindowController: overlay)
        }
        
        accessibilityMonitor?.start()
    }
}
