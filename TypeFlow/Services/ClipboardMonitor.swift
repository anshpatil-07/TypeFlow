import Cocoa
import Foundation

enum ClipboardType {
    case url
    case email
    case code
    case prose
    case unknown
}

/// Monitors the system clipboard and maintains a rolling in-memory array of
/// the last 3 unique text items the user has copied.
/// Items are capped at 500 characters to prevent memory bloat.
class ClipboardMonitor {
    static let shared = ClipboardMonitor()

    private let maxItems = 3
    private let maxCharacters = 500

    /// The rolling list of recent clipboard text items (most recent last).
    private(set) var recentItems: [String] = []
    
    private(set) var currentClipboardType: ClipboardType = .unknown

    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var timer: Timer?

    private init() {}

    /// Starts polling the clipboard for changes every 0.5 seconds.
    func start() {
        timer = Timer.scheduledTimer(
            timeInterval: 0.5,
            target: self,
            selector: #selector(checkClipboard),
            userInfo: nil,
            repeats: true
        )
        timer?.tolerance = 0.1
    }

    /// Stops the clipboard polling timer.
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    @objc private func checkClipboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        guard let rawString = pasteboard.string(forType: .string), !rawString.isEmpty else { return }

        // Truncate to max character limit
        let item = rawString.count > maxCharacters
            ? String(rawString.prefix(maxCharacters))
            : rawString

        // Only store if it differs from the most recently stored item
        if item != recentItems.last {
            recentItems.append(item)
            // Keep only the last `maxItems` unique entries
            if recentItems.count > maxItems {
                recentItems.removeFirst()
            }
            classifyClipboardType(item)
        }
    }
    
    private func classifyClipboardType(_ text: String) {
        let lowercased = text.lowercased()
        
        // URL classification
        if lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://") || lowercased.hasPrefix("www.") {
            currentClipboardType = .url
            return
        }
        
        // Email classification
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        if text.range(of: emailRegex, options: .regularExpression) != nil {
            currentClipboardType = .email
            return
        }
        
        // Code classification
        if text.contains("{") && text.contains("}") && text.contains(";") || text.contains("def ") || text.contains("func ") {
            currentClipboardType = .code
            return
        }
        
        // Prose fallback
        if text.components(separatedBy: .whitespacesAndNewlines).count > 3 {
            currentClipboardType = .prose
            return
        }
        
        currentClipboardType = .unknown
    }
}
