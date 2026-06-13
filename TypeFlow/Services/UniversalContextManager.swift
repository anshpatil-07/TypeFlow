import Foundation
import AppKit

struct CurrentContext {
    let appBundleId: String
    let appTitle: String
    let screenKeywords: [String]
    let clipboardType: ClipboardType
}

class UniversalContextManager {
    static let shared = UniversalContextManager()
    
    var latestContext: CurrentContext
    
    private init() {
        self.latestContext = CurrentContext(
            appBundleId: "unknown",
            appTitle: "unknown",
            screenKeywords: [],
            clipboardType: .unknown
        )
    }
    
    func refreshContext() {
        let app = NSWorkspace.shared.frontmostApplication
        let bundleId = app?.bundleIdentifier ?? "unknown"
        let title = app?.localizedName ?? "unknown"
        
        let screenText = ScreenContextManager.shared.latestScreenText
        let screenKeywords = extractKeywords(from: screenText)
        
        let clipboardType = ClipboardMonitor.shared.currentClipboardType
        
        self.latestContext = CurrentContext(
            appBundleId: bundleId,
            appTitle: title,
            screenKeywords: screenKeywords,
            clipboardType: clipboardType
        )
        
        print("[TypeFlow-Debug] UniversalContextManager: Refreshed Context. App: \(title), Clipboard: \(clipboardType), Keywords: \(screenKeywords.prefix(5))")
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
