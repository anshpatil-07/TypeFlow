import Foundation

class VocabularyExtractor {
    static let shared = VocabularyExtractor()
    
    private var vocabulary: [String] = []
    private let fileURL: URL
    private var timer: Timer?
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let typeFlowDir = appSupport.appendingPathComponent("TypeFlow")
        fileURL = typeFlowDir.appendingPathComponent("vocabulary.json")
        
        loadVocabulary()
        
        // Asynchronously process on launch
        DispatchQueue.global(qos: .background).async {
            self.extractVocabulary()
        }
        
        // Process once a day (every 24 hours)
        DispatchQueue.main.async {
            self.timer = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { _ in
                DispatchQueue.global(qos: .background).async {
                    self.extractVocabulary()
                }
            }
        }
    }
    
    func getVocabulary() -> [String] {
        return vocabulary
    }
    
    func extractVocabulary() {
        guard SettingsManager.shared.personalizationEnabled else {
            print("[TypeFlow-Debug] VocabularyExtractor: Personalization disabled, skipping extraction")
            return
        }
        
        let history = TypingHistoryManager.shared.getHistory()
        guard !history.isEmpty else {
            print("[TypeFlow-Debug] VocabularyExtractor: History is empty, skipping extraction")
            return
        }
        
        print("[TypeFlow-Debug] VocabularyExtractor: Starting vocabulary extraction on \(history.count) history sentences...")
        let stopwords: Set<String> = [
            "the", "and", "a", "of", "to", "in", "is", "you", "that", "it", 
            "he", "was", "for", "on", "are", "as", "with", "his", "they", 
            "i", "at", "be", "this", "have", "from", "or", "one", "had", 
            "by", "word", "but", "not", "what", "all", "were", "we", "when", 
            "your", "can", "said", "there", "use", "an", "each", "which", 
            "she", "do", "how", "their", "if", "will", "up", "other", "about", 
            "out", "many", "then", "them", "these", "so", "some", "her", 
            "would", "make", "like", "him", "into", "time", "has", "look", 
            "two", "more", "write", "go", "see", "number", "no", "way", 
            "could", "people", "my", "than", "first", "water", "been", "call", 
            "who", "oil", "its", "now", "find", "long", "down", "day", 
            "did", "get", "come", "made", "may", "part", "with", "this", 
            "that", "from", "your", "them", "then", "they"
        ]
        
        var wordCounts: [String: Int] = [:]
        
        for sentence in history {
            let cleaned = sentence.lowercased()
            let words = cleaned.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.count >= 4 && !stopwords.contains($0) }
            
            for word in words {
                wordCounts[word, default: 0] += 1
            }
        }
        
        // Find top 15 words that appear at least twice
        let sortedWords = wordCounts.filter { $0.value >= 2 }
            .sorted { $0.value > $1.value }
            .map { $0.key }
        
        let topWords = Array(sortedWords.prefix(15))
        
        DispatchQueue.main.async {
            self.vocabulary = topWords
            self.saveVocabulary()
            print("[TypeFlow-Debug] VocabularyExtractor: Successfully extracted \(topWords.count) vocabulary words: \(topWords)")
        }
    }
    
    private func loadVocabulary() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            vocabulary = []
            return
        }
        vocabulary = decoded
    }
    
    private func saveVocabulary() {
        if let data = try? JSONEncoder().encode(vocabulary) {
            try? data.write(to: fileURL)
        }
    }
}
