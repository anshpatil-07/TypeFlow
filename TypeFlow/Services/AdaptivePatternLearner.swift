import Foundation

struct LearnedBehaviors: Codable {
    var clipboardTriggers: [String] = []
    var stopWords: [String] = []
}

class AdaptivePatternLearner {
    static let shared = AdaptivePatternLearner()
    
    private let storageURL: URL
    private(set) var behaviors: LearnedBehaviors
    
    private var idleTimer: Timer?
    private let idleThreshold: TimeInterval = 180 // 3 minutes
    
    private init() {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        storageURL = paths[0].appendingPathComponent("learned_behaviors.json")
        behaviors = LearnedBehaviors()
        loadBehaviors()
        
        NotificationCenter.default.addObserver(self, selector: #selector(resetIdleTimer), name: Notification.Name("UserDidType"), object: nil)
        resetIdleTimer()
    }
    
    @objc private func resetIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: idleThreshold, repeats: false) { [weak self] _ in
            self?.performPatternExtraction()
        }
    }
    
    func reportCancelledGeneration(after word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return }
        // Simple heuristic: if cancelled frequently, could add to stopWords. 
        // For now, we will track this in memory and eventually persist.
    }
    
    private func performPatternExtraction() {
        print("[TypeFlow-Debug] AdaptivePatternLearner: Idle threshold reached. Running pattern extraction.")
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            let history = TypingHistoryManager.shared.getHistory()
            guard !history.isEmpty else { return }
            
            var newTriggers = Set(self.behaviors.clipboardTriggers)
            
            let urlRegex = try! NSRegularExpression(pattern: "https?://[^\\s]+")
            let emailRegex = try! NSRegularExpression(pattern: "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}")
            
            for sentence in history {
                let range = NSRange(sentence.startIndex..., in: sentence)
                if urlRegex.firstMatch(in: sentence, options: [], range: range) != nil ||
                   emailRegex.firstMatch(in: sentence, options: [], range: range) != nil {
                    
                    let parts = sentence.components(separatedBy: .whitespaces)
                    if parts.count > 2 {
                        let triggerPhrase = parts.dropLast().suffix(3).joined(separator: " ")
                        if !triggerPhrase.isEmpty && triggerPhrase.count > 5 {
                            newTriggers.insert(triggerPhrase)
                        }
                    }
                }
            }
            
            DispatchQueue.main.async {
                self.behaviors.clipboardTriggers = Array(newTriggers)
                self.saveBehaviors()
                print("[TypeFlow-Debug] AdaptivePatternLearner: Extraction complete. Learned \(self.behaviors.clipboardTriggers.count) clipboard triggers.")
            }
        }
    }
    
    func deleteBehavior(trigger: String) {
        behaviors.clipboardTriggers.removeAll { $0 == trigger }
        saveBehaviors()
    }
    
    func deleteStopWord(word: String) {
        behaviors.stopWords.removeAll { $0 == word }
        saveBehaviors()
    }
    
    private func loadBehaviors() {
        if let data = try? Data(contentsOf: storageURL),
           let decoded = try? JSONDecoder().decode(LearnedBehaviors.self, from: data) {
            self.behaviors = decoded
        } else {
            // Default baseline behaviors
            self.behaviors = LearnedBehaviors(
                clipboardTriggers: ["here is the link:", "my email is", "the url is"],
                stopWords: ["the", "and", "is", "a", "to", "in", "of", "it", "that", "on", "for"]
            )
            saveBehaviors()
        }
    }
    
    private func saveBehaviors() {
        if let data = try? JSONEncoder().encode(behaviors) {
            try? data.write(to: storageURL)
        }
    }
}
