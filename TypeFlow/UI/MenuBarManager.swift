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
        
        menu.addItem(NSMenuItem(title: "Dashboard...", action: #selector(openDashboard), keyEquivalent: "d"))
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Clear Typing History", action: #selector(clearHistory), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        
        // Use standard actions
        menu.items.forEach { $0.target = self }
        
        self.statusItem.menu = menu
        
        // Handle launch at login registration
        try? SMAppService.mainApp.register()
    }
    
    var settingsWindow: NSWindow?
    var dashboardWindow: NSWindow?
    
    @objc func openSettings() {
        if settingsWindow == nil {
            let tabVC = SettingsTabViewController()
            let window = NSWindow(contentViewController: tabVC)
            window.title = "TypeFlow Settings"
            window.styleMask.insert(.closable)
            window.styleMask.insert(.miniaturizable)
            window.styleMask.insert(.titled)
            window.styleMask.remove(.resizable)
            window.standardWindowButton(.zoomButton)?.isEnabled = false
            window.setContentSize(NSSize(width: 750, height: 550))
            window.center()
            window.isReleasedWhenClosed = false
            self.settingsWindow = window
        }
        
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

// ─── Native Settings Tab Controller ─────────────────────────────────────────────

class SettingsTabViewController: NSTabViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        self.tabStyle = .toolbar
        
        func addTab<V: View>(title: String, icon: String, view: V) {
            let vc = NSHostingController(rootView: view.frame(maxWidth: .infinity, maxHeight: .infinity))
            vc.title = title
            let item = NSTabViewItem(viewController: vc)
            item.label = title
            item.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
            self.addTabViewItem(item)
        }
        
        addTab(title: "General", icon: "gear", view: GeneralSettingsView())
        addTab(title: "Shortcuts", icon: "keyboard", view: ShortcutsSettingsView())
        addTab(title: "Models", icon: "cpu", view: ModelsSettingsView())
        addTab(title: "Tones", icon: "person.text.rectangle", view: TonesSettingsView())
        addTab(title: "Snippets", icon: "text.badge.plus", view: SnippetsSettingsView())
        addTab(title: "Apps", icon: "app.badge", view: AppOverridesSettingsView())
        addTab(title: "Behaviors", icon: "brain.head.profile", view: LearnedBehaviorsView())
    }
}

    @objc func openDashboard() {
        if dashboardWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 700, height: 520),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered, defer: false)
            window.title = "TypeFlow Dashboard"
            window.isReleasedWhenClosed = false
            window.center()
            self.dashboardWindow = window
        }
        dashboardWindow?.contentView = NSHostingView(rootView: DashboardView())
        NSApp.activate(ignoringOtherApps: true)
        dashboardWindow?.makeKeyAndOrderFront(nil)
    }
    
    @objc func clearHistory() {
        TypingHistoryManager.shared.clearHistory()
        let alert = NSAlert()
        alert.messageText = "Typing History Cleared"
        alert.informativeText = "Your local typing history database has been successfully purged."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
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
