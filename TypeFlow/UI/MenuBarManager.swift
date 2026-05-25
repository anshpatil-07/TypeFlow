import Cocoa
import SwiftUI
import ServiceManagement

class MenuBarManager {
    var statusItem: NSStatusItem!
    
    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "text.bubble.fill", accessibilityDescription: "TypeFlow")
        }
        
        setupMenu()
        
        NotificationCenter.default.addObserver(
            forName: Notification.Name("TypeFlowModelLoadingStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let isLoading = notification.object as? Bool {
                self?.updateStatusItemIcon(isLoading: isLoading)
            }
        }
    }
    
    func setupMenu() {
        let menu = NSMenu()
        
        let statusItem = NSMenuItem(title: "TypeFlow is active", action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        
        // Use standard actions
        menu.items.forEach { $0.target = self }
        
        self.statusItem.menu = menu
        
        // Handle launch at login registration
        try? SMAppService.mainApp.register()
    }
    
    var settingsWindow: NSWindow?
    
    @objc func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 450),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered, defer: false)
            window.title = "TypeFlow Settings"
            window.isReleasedWhenClosed = false
            window.center()
            self.settingsWindow = window
        }
        
        // Always refresh the content view to pick up any code changes
        settingsWindow?.contentView = NSHostingView(rootView: SettingsView().frame(width: 600, height: 450))
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    
    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }
    
    func updateStatusItemIcon(isLoading: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let button = self.statusItem.button else { return }
            let symbolName = isLoading ? "ellipsis.bubble.fill" : "text.bubble.fill"
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "TypeFlow")
        }
    }
}
