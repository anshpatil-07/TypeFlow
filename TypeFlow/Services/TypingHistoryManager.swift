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
        } else {
            let newKey = SymmetricKey(size: .bits256)
            let newKeyData = newKey.withUnsafeBytes { Data($0) }
            if KeychainHelper.save(key: keyName, data: newKeyData) {
                symmetricKey = newKey
            }
        }
        
        loadHistory()
    }
    
    func logSentence(_ sentence: String) {
        guard SettingsManager.shared.personalizationEnabled else { return }
        
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        // Don't add duplicate adjacent sentences
        if history.last == trimmed { return }
        
        history.append(trimmed)
        
        // Enforce rolling window of 1,000 sentences
        if history.count > 1000 {
            history.removeFirst(history.count - 1000)
        }
        
        saveHistory()
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
            let shuffled = remaining.shuffled()
            selected.append(contentsOf: shuffled.prefix(needed))
        }
        
        return selected
    }
    
    private func saveHistory() {
        guard let key = symmetricKey else { return }
        if let data = try? JSONEncoder().encode(history),
           let sealedBox = try? AES.GCM.seal(data, using: key) {
            try? sealedBox.combined?.write(to: fileURL)
        }
    }
    
    private func loadHistory() {
        guard let key = symmetricKey,
              let encryptedData = try? Data(contentsOf: fileURL),
              let sealedBox = try? AES.GCM.SealedBox(combined: encryptedData),
              let decryptedData = try? AES.GCM.open(sealedBox, using: key),
              let decoded = try? JSONDecoder().decode([String].self, from: decryptedData) else {
            history = []
            return
        }
        history = decoded
    }
}
