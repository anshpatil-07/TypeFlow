import Foundation
import AppKit

struct ScreenSnapshot: Equatable {
    let appBundleId: String
    let appTitle: String
    let windowTitle: String?
    let screenText: String
    
    static func == (lhs: ScreenSnapshot, rhs: ScreenSnapshot) -> Bool {
        return lhs.appTitle == rhs.appTitle && 
               lhs.windowTitle == rhs.windowTitle && 
               lhs.screenText == rhs.screenText
    }
}

struct CurrentContext {
    let appBundleId: String
    let appTitle: String
    let windowTitle: String?
    let screenKeywords: [String]
    let clipboardType: ClipboardType
}

class UniversalContextManager {
    static let shared = UniversalContextManager()
    
    var latestContext: CurrentContext
    private(set) var contextHistory: [ScreenSnapshot] = []
    
    private init() {
        self.latestContext = CurrentContext(
            appBundleId: "unknown",
            appTitle: "unknown",
            windowTitle: nil,
            screenKeywords: [],
            clipboardType: .unknown
        )
    }
    
    private func getActiveWindowTitle(for app: NSRunningApplication?) -> String? {
        guard let app = app else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        
        var window: CFTypeRef?
        
        // Try focused window first
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &window) != .success {
            // Fallback to main window if focused window fails
            AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &window)
        }
        
        if let activeWindow = window {
            var titleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(activeWindow as! AXUIElement, kAXTitleAttribute as CFString, &titleRef) == .success,
               let title = titleRef as? String {
                return title
            }
        }
        return nil
    }
    
    func refreshContext() {
        // Snapshot the outgoing state before updating to the new one
        let oldContext = self.latestContext
        let oldScreenText = ScreenContextManager.shared.latestScreenText
        
        // Only push if it's a known valid app, not the default "unknown"
        if oldContext.appBundleId != "unknown" {
            self.updateHistory(
                appBundleId: oldContext.appBundleId,
                appTitle: oldContext.appTitle,
                windowTitle: oldContext.windowTitle,
                screenText: oldScreenText
            )
        }
        
        let app = NSWorkspace.shared.frontmostApplication
        let bundleId = app?.bundleIdentifier ?? "unknown"
        let title = app?.localizedName ?? "unknown"
        let windowTitle = getActiveWindowTitle(for: app)
        
        let screenText = ScreenContextManager.shared.latestScreenText
        let screenKeywords = extractKeywords(from: screenText)
        
        let clipboardType = ClipboardMonitor.shared.currentClipboardType
        
        self.latestContext = CurrentContext(
            appBundleId: bundleId,
            appTitle: title,
            windowTitle: windowTitle,
            screenKeywords: screenKeywords,
            clipboardType: clipboardType
        )
        
        print("[TypeFlow-Debug] UniversalContextManager: Refreshed Context. App: \(title), Window: \(windowTitle ?? "nil"), Clipboard: \(clipboardType)")
    }
    
    func updateHistory(appBundleId: String, appTitle: String, windowTitle: String?, screenText: String) {
        let newSnapshot = ScreenSnapshot(
            appBundleId: appBundleId,
            appTitle: appTitle,
            windowTitle: windowTitle,
            screenText: screenText
        )
        
        if contextHistory.isEmpty || contextHistory.last != newSnapshot {
            // Avoid adding identical consecutive snapshots
            if let last = contextHistory.last, last.screenText == screenText && last.appTitle == appTitle {
                return
            }
            
            contextHistory.append(newSnapshot)
            if contextHistory.count > 2 {
                contextHistory.removeFirst()
            }
            print("[TypeFlow-Debug] UniversalContextManager: Pushed new snapshot to history. Stack size: \(contextHistory.count)")
        }
    }
    
    // For TQB testing purposes
    func clearHistory() {
        contextHistory.removeAll()
    }
    
    private func extractKeywords(from text: String) -> [String] {
        let stopWords: Set<String> = ["the", "and", "is", "in", "it", "to", "of", "a", "that", "on", "for", "with", "as", "by", "this", "or", "are", "be", "from", "at", "an", "was"]
        let words = text.lowercased().components(separatedBy: .alphanumerics.inverted).filter { !$0.isEmpty }
        
        var frequencies: [String: Int] = [:]
        for word in words {
            guard word.count > 3, !stopWords.contains(word) else { continue }
            frequencies[word, default: 0] += 1
        }
        
        let sorted = frequencies.sorted { $0.value > $1.value }
        return sorted.prefix(15).map { $0.key }
    }
}
