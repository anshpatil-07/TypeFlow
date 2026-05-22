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
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered, defer: false)
            window.title = "TypeFlow Settings"
            window.contentView = NSHostingView(rootView: SettingsView())
            window.center()
            window.isReleasedWhenClosed = false
            self.settingsWindow = window
        }
        
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }
}
