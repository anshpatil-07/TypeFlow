import Foundation

// MARK: - Data Models

struct DayStats: Codable {
    var date: String                // "YYYY-MM-DD"
    var completionsShown: Int = 0
    var completionsAccepted: Int = 0
    var charactersSaved: Int = 0
    var snippetsFired: Int = 0
    var spellCorrections: Int = 0
}

struct AllTimeStats {
    var totalCompletionsShown: Int
    var totalCompletionsAccepted: Int
    var totalCharactersSaved: Int
    var totalSnippetsFired: Int
    var totalSpellCorrections: Int
    var wordsSaved: Int { totalCharactersSaved / 5 }
    var acceptanceRate: Double {
        guard totalCompletionsShown > 0 else { return 0 }
        return Double(totalCompletionsAccepted) / Double(totalCompletionsShown) * 100
    }
}

// MARK: - Manager

class UsageStatsManager {
    static let shared = UsageStatsManager()

    private var dailyStats: [String: DayStats] = [:]
    private let fileURL: URL
    private var saveWorkItem: DispatchWorkItem?

    private var todayKey: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let typeFlowDir = appSupport.appendingPathComponent("TypeFlow")
        try? FileManager.default.createDirectory(at: typeFlowDir, withIntermediateDirectories: true)
        fileURL = typeFlowDir.appendingPathComponent("stats.json")
        load()
    }

    // MARK: - Record Events

    func recordCompletionShown() {
        dailyStats[todayKey, default: DayStats(date: todayKey)].completionsShown += 1
        scheduleSave()
    }

    func recordCompletionAccepted(charactersSaved: Int) {
        dailyStats[todayKey, default: DayStats(date: todayKey)].completionsAccepted += 1
        dailyStats[todayKey, default: DayStats(date: todayKey)].charactersSaved += charactersSaved
        scheduleSave()
    }

    func recordSnippetFired() {
        dailyStats[todayKey, default: DayStats(date: todayKey)].snippetsFired += 1
        scheduleSave()
    }

    func recordSpellCorrection() {
        dailyStats[todayKey, default: DayStats(date: todayKey)].spellCorrections += 1
        scheduleSave()
    }

    // MARK: - Query

    func getDailyStats(days: Int = 30) -> [DayStats] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return (0..<days).reversed().compactMap { offset -> DayStats? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            let key = formatter.string(from: date)
            return dailyStats[key] ?? DayStats(date: key)
        }
    }

    func getAllTimeStats() -> AllTimeStats {
        let values = dailyStats.values
        return AllTimeStats(
            totalCompletionsShown: values.reduce(0) { $0 + $1.completionsShown },
            totalCompletionsAccepted: values.reduce(0) { $0 + $1.completionsAccepted },
            totalCharactersSaved: values.reduce(0) { $0 + $1.charactersSaved },
            totalSnippetsFired: values.reduce(0) { $0 + $1.snippetsFired },
            totalSpellCorrections: values.reduce(0) { $0 + $1.spellCorrections }
        )
    }

    func resetStats() {
        dailyStats = [:]
        try? FileManager.default.removeItem(at: fileURL)
        print("[TypeFlow-Debug] UsageStatsManager: Stats reset")
    }

    // MARK: - Persistence

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.save() }
        saveWorkItem = workItem
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(dailyStats)
            try data.write(to: fileURL)
        } catch {
            print("[TypeFlow-Debug] UsageStatsManager: ERROR saving stats: \(error)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: DayStats].self, from: data) else {
            print("[TypeFlow-Debug] UsageStatsManager: No existing stats file, starting fresh")
            return
        }
        dailyStats = decoded
        print("[TypeFlow-Debug] UsageStatsManager: Loaded stats for \(decoded.count) days")
    }
}
