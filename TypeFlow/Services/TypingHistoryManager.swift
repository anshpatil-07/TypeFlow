import Foundation
import Security
import CryptoKit

class KeychainHelper {
    static func save(key: String, data: Data) -> Bool {
        let query = [
            kSecClass as String       : kSecClassGenericPassword as String,
            kSecAttrAccount as String : key,
            kSecValueData as String   : data
        ] as [String : Any]
        
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    static func load(key: String) -> Data? {
        let query = [
            kSecClass as String       : kSecClassGenericPassword as String,
            kSecAttrAccount as String : key,
            kSecReturnData as String  : kCFBooleanTrue!,
            kSecMatchLimit as String  : kSecMatchLimitOne
        ] as [String : Any]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        if status == errSecSuccess {
            return dataTypeRef as? Data
        }
        return nil
    }
}

class TypingHistoryManager {
    static let shared = TypingHistoryManager()
    
    private var history: [String] = []
    private let fileURL: URL
    private var symmetricKey: SymmetricKey?
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let typeFlowDir = appSupport.appendingPathComponent("TypeFlow")
        try? FileManager.default.createDirectory(at: typeFlowDir, withIntermediateDirectories: true)
        fileURL = typeFlowDir.appendingPathComponent("history.enc")
        
        let keyName = "com.cotyper.TypeFlow.historyKey"
        if let keyData = KeychainHelper.load(key: keyName) {
            symmetricKey = SymmetricKey(data: keyData)
            print("[TypeFlow-Debug] TypingHistoryManager: Loaded existing symmetric key from Keychain")
        } else {
            let newKey = SymmetricKey(size: .bits256)
            let newKeyData = newKey.withUnsafeBytes { Data($0) }
            if KeychainHelper.save(key: keyName, data: newKeyData) {
                symmetricKey = newKey
                print("[TypeFlow-Debug] TypingHistoryManager: Generated and saved new symmetric key to Keychain")
            } else {
                print("[TypeFlow-Debug] TypingHistoryManager: ERROR - Failed to save key to Keychain!")
            }
        }
        
        loadHistory()
    }
    
    func logSentence(_ sentence: String) {
        guard SettingsManager.shared.personalizationEnabled else {
            print("[TypeFlow-Debug] TypingHistoryManager: Personalization disabled, skipping logSentence for: '\(sentence)'")
            return
        }
        
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let words = trimmed.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard words.count >= 3 else {
            print("[TypeFlow-Debug] TypingHistoryManager: Skipping short sentence (< 3 words): '\(trimmed)'")
            return
        }
        
        let avgWordLength = words.reduce(0) { $0 + $1.count } / words.count
        guard avgWordLength >= 2 else {
            print("[TypeFlow-Debug] TypingHistoryManager: Skipping likely gibberish testing string: '\(trimmed)'")
            return
        }
        
        // Don't add duplicate adjacent sentences
        if history.last == trimmed {
            print("[TypeFlow-Debug] TypingHistoryManager: Skipping duplicate adjacent sentence: '\(trimmed)'")
            return
        }
        
        history.append(trimmed)
        print("[TypeFlow-Debug] TypingHistoryManager: Logged sentence: '\(trimmed)' (total history items: \(history.count))")
        
        // Enforce rolling window of 1,000 sentences
        if history.count > 1000 {
            history.removeFirst(history.count - 1000)
        }
        
        saveHistory()
        
        // Dynamically update custom vocabulary after a sentence is logged
        VocabularyExtractor.shared.extractVocabulary()
    }
    
    func logSentenceFromText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let lastChar = trimmed.last!
        let sentenceBoundaries: Set<Character> = [".", "?", "!"]
        guard sentenceBoundaries.contains(lastChar) else { return }
        
        let chars = Array(trimmed)
        var startIndex = 0
        if chars.count > 1 {
            for i in (0..<(chars.count - 1)).reversed() {
                let char = chars[i]
                if sentenceBoundaries.contains(char) {
                    startIndex = i + 1
                    break
                }
            }
        }
        
        let sentence = String(chars[startIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if sentence.count >= 5 {
            logSentence(sentence)
        }
    }
    
    
    func getHistory() -> [String] {
        return history
    }
    
    func clearHistory() {
        history.removeAll()
        saveHistory()
        print("[TypeFlow-Debug] TypingHistoryManager: History cleared.")
        VocabularyExtractor.shared.extractVocabulary()
    }
    
    func getRelevantSamples(for text: String, count: Int) -> [String] {
        guard !history.isEmpty else { return [] }
        
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 4 }
        
        var scoredSentences: [(sentence: String, score: Int)] = []
        for sentence in history {
            var score = 0
            let sentenceLower = sentence.lowercased()
            for word in words {
                if sentenceLower.contains(word) {
                    score += 1
                }
            }
            if score > 0 {
                scoredSentences.append((sentence, score))
            }
        }
        
        scoredSentences.sort(by: { $0.score > $1.score })
        
        var selected: [String] = []
        for item in scoredSentences.prefix(count) {
            selected.append(item.sentence)
        }
        
        if selected.count < count {
            let needed = count - selected.count
            let remaining = history.filter { !selected.contains($0) }
            // Use stable suffix instead of shuffled() to prevent breaking the LLM KV cache on every keystroke
            selected.append(contentsOf: remaining.suffix(needed))
        }
        
        return selected
    }
    
    /// Returns the N most recent history sentences without topic-matching.
    /// Used for KV cache prefix prefill so the static prefix stays stable
    /// across keystrokes (unlike getRelevantSamples which changes per text).
    func getRecentSamples(count: Int) -> [String] {
        return Array(history.suffix(count))
    }
    
    private func saveHistory() {
        guard let key = symmetricKey else {
            print("[TypeFlow-Debug] TypingHistoryManager: saveHistory failed - symmetricKey is nil")
            return
        }
        do {
            let data = try JSONEncoder().encode(history)
            let sealedBox = try AES.GCM.seal(data, using: key)
            try sealedBox.combined?.write(to: fileURL)
            print("[TypeFlow-Debug] TypingHistoryManager: Saved \(history.count) history items to disk (encrypted)")
        } catch {
            print("[TypeFlow-Debug] TypingHistoryManager: ERROR saving history: \(error)")
        }
    }
    
    private func loadHistory() {
        guard let key = symmetricKey else {
            print("[TypeFlow-Debug] TypingHistoryManager: loadHistory failed - symmetricKey is nil")
            history = []
            return
        }
        do {
            let encryptedData = try Data(contentsOf: fileURL)
            let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
            let decryptedData = try AES.GCM.open(sealedBox, using: key)
            let decoded = try JSONDecoder().decode([String].self, from: decryptedData)
            history = decoded
            print("[TypeFlow-Debug] TypingHistoryManager: Loaded \(history.count) history items from disk (decrypted)")
        } catch {
            print("[TypeFlow-Debug] TypingHistoryManager: ERROR loading history: \(error)")
            history = []
        }
    }
    
    func getSuggestedSnippets() -> [(text: String, suggestedShortcode: String)] {
        guard SettingsManager.shared.personalizationEnabled else { return [] }
        
        // Count frequencies of all history items
        var counts: [String: Int] = [:]
        for sentence in history {
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 20 else { continue }
            counts[trimmed, default: 0] += 1
        }
        
        // Filter those with count >= 3
        let repetitive = counts.filter { $0.value >= 3 }
        
        // Get active snippets to avoid suggesting already-registered ones
        let activeSnippets = SettingsManager.shared.getSnippets()
        let activeReplacementValues = Set(activeSnippets.values)
        
        var suggestions: [(text: String, suggestedShortcode: String)] = []
        
        // Sort by frequency (highest first)
        let sortedRepetitive = repetitive.sorted { $0.value > $1.value }
        
        for (phrase, _) in sortedRepetitive {
            // Skip if it's already a snippet replacement value
            if activeReplacementValues.contains(phrase) {
                continue
            }
            
            // Generate a suggested shortcode:
            // e.g. "Best regards," -> take initials or first 3-4 chars of first word
            let cleanPhrase = phrase.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
            
            var shortcode = ""
            if let firstWord = cleanPhrase.first?.lowercased() {
                shortcode = "/" + String(firstWord.prefix(4))
            } else {
                shortcode = "/snip"
            }
            
            // Avoid duplicate suggested shortcodes in the returned list
            if !suggestions.contains(where: { $0.suggestedShortcode == shortcode }) {
                suggestions.append((text: phrase, suggestedShortcode: shortcode))
            } else {
                var suffixNum = 2
                var newShortcode = "\(shortcode)\(suffixNum)"
                while suggestions.contains(where: { $0.suggestedShortcode == newShortcode }) {
                    suffixNum += 1
                    newShortcode = "\(shortcode)\(suffixNum)"
                }
                suggestions.append((text: phrase, suggestedShortcode: newShortcode))
            }
        }
        
        return suggestions
    }
}

