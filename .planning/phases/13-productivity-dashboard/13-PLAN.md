---
id: 13-01
wave: 1
title: Stats Infrastructure — UsageStatsManager
depends_on: []
files_modified:
  - TypeFlow/Services/UsageStatsManager.swift
  - TypeFlow/Services/CompletionManager.swift
requirements: []
autonomous: true
---

<objective>
Create `UsageStatsManager`, a lightweight singleton that persists daily usage counters to `~/Library/Application Support/TypeFlow/stats.json`. Add 4 instrumentation call sites in `CompletionManager` to record completions shown, completions accepted, snippets fired, and spell corrections.
</objective>

<context>
TypeFlow stores all data in `~/Library/Application Support/TypeFlow/`. The existing pattern (from `TypingHistoryManager` and `SettingsManager`) is to use a file URL constructed from `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)`. Stats are aggregate numbers (no personal text), so no encryption is needed — plain JSON is fine.

The 4 instrumentation call sites in `CompletionManager.swift`:
1. **Completion shown** — line ~363, inside the `DispatchQueue.main.async` block, inside `if !processedCompletion.isEmpty` before `overlayWindowController?.updateText(processedCompletion)`
2. **AI completion accepted** — line ~415-422, inside `handleTabPressed()`, in the `if let completion = currentCompletion, !completion.isEmpty` branch, before `TextInjector.shared.inject(text: completion)`
3. **Snippet fired** — line ~397-412, inside `handleTabPressed()`, in the `if let snippetKey = activeSnippetKey` branch, before `TextInjector.shared.injectBackspaces(count: deleteCount)`
4. **Spell correction accepted** — line ~381-394, inside `handleTabPressed()`, in the `if let spellCorrection = activeSpellCorrection` branch, before `TextInjector.shared.injectBackspaces(count: deleteCount)`
</context>

<read_first>
- TypeFlow/Services/CompletionManager.swift — read entire file to understand exact line numbers for all 4 instrumentation sites
- TypeFlow/Services/TypingHistoryManager.swift — reference for the Application Support file URL construction pattern
- TypeFlow/Services/SettingsManager.swift — reference for the Application Support file URL construction pattern
</read_first>

<action>
**Step 1: Create `TypeFlow/Services/UsageStatsManager.swift`**

Create this file with the following exact implementation:

```swift
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
```

**Step 2: Add 4 instrumentation calls in `CompletionManager.swift`**

**Site 1 — Completion shown** (inside the `DispatchQueue.main.async` block in `triggerGeneration`, inside the `if !processedCompletion.isEmpty` branch):

Find this block:
```swift
if !processedCompletion.isEmpty {
    if let rect = self.accessibilityMonitor?.getCurrentCaretRect() {
```

Add immediately before the `if let rect` line:
```swift
UsageStatsManager.shared.recordCompletionShown()
```

**Site 2 — AI completion accepted** (in `handleTabPressed()`, in the `if let completion = currentCompletion, !completion.isEmpty` branch):

Find:
```swift
if let completion = currentCompletion, !completion.isEmpty {
    let activeLine = accessibilityMonitor?.getTextBeforeCaret() ?? ""
    TypingHistoryManager.shared.logSentence(activeLine + completion)
    
    // Inject the text
    TextInjector.shared.inject(text: completion)
```

Add before `TextInjector.shared.inject(text: completion)`:
```swift
UsageStatsManager.shared.recordCompletionAccepted(charactersSaved: completion.count)
```

**Site 3 — Snippet accepted** (in `handleTabPressed()`, in the `if let snippetKey = activeSnippetKey` branch):

Find:
```swift
if let snippetKey = activeSnippetKey, let rawCompletion = currentCompletion {
    let activeLine = accessibilityMonitor?.getTextBeforeCaret() ?? ""
    let resolved = resolveSnippetPlaceholders(rawCompletion)
    let (finalText, cursorOffset) = processCursorPlaceholder(resolved)
    
    TypingHistoryManager.shared.logSentence(activeLine + finalText)
    
    // Delete the shortcode
    let deleteCount = snippetKey.count
    TextInjector.shared.injectBackspaces(count: deleteCount)
```

Add before `TextInjector.shared.injectBackspaces(count: deleteCount)`:
```swift
UsageStatsManager.shared.recordSnippetFired()
```

**Site 4 — Spell correction accepted** (in `handleTabPressed()`, in the `if let spellCorrection = activeSpellCorrection` branch):

Find:
```swift
TextInjector.shared.injectBackspaces(count: deleteCount)
TextInjector.shared.inject(text: spellCorrection.corrected)
```
(The first occurrence of injectBackspaces in handleTabPressed, in the spell correction branch.)

Add before `TextInjector.shared.injectBackspaces(count: deleteCount)`:
```swift
UsageStatsManager.shared.recordSpellCorrection()
```
</action>

<acceptance_criteria>
- `TypeFlow/Services/UsageStatsManager.swift` exists and contains `class UsageStatsManager`, `struct DayStats`, `struct AllTimeStats`
- `UsageStatsManager.swift` contains `func recordCompletionShown()`, `func recordCompletionAccepted(charactersSaved:)`, `func recordSnippetFired()`, `func recordSpellCorrection()`
- `UsageStatsManager.swift` contains `func getDailyStats(days:)`, `func getAllTimeStats()`, `func resetStats()`
- `CompletionManager.swift` contains `UsageStatsManager.shared.recordCompletionShown()`
- `CompletionManager.swift` contains `UsageStatsManager.shared.recordCompletionAccepted(charactersSaved: completion.count)`
- `CompletionManager.swift` contains `UsageStatsManager.shared.recordSnippetFired()`
- `CompletionManager.swift` contains `UsageStatsManager.shared.recordSpellCorrection()`
- `xcodebuild -scheme TypeFlow build` succeeds with no errors
</acceptance_criteria>

---
id: 13-02
wave: 2
title: Dashboard UI — DashboardView
depends_on: [13-01]
files_modified:
  - TypeFlow/UI/DashboardView.swift
  - TypeFlow/UI/MenuBarManager.swift
requirements: []
autonomous: true
---

<objective>
Create `DashboardView.swift` — a native SwiftUI macOS window showing all-time stats, a 30-day bar chart, and snippet/history rows. Wire it into `MenuBarManager` with a "Dashboard..." menu item and a dedicated `NSWindow`.
</objective>

<context>
The existing Settings window in `MenuBarManager.swift` uses `NSWindow` + `NSHostingView` (see `openSettings()` and `var settingsWindow: NSWindow?`). The Dashboard must use the exact same pattern. The `Charts` framework has been available since macOS 13+, and this project targets macOS 14+, so `import Charts` compiles safely.

The DashboardView layout:
1. **Header row** — 4 stat cards: Completions Accepted, Characters Saved, Words Saved, Acceptance Rate %
2. **30-day bar chart** — `BarMark` per day, y = completionsAccepted, using `Charts` framework
3. **Secondary stats row** — Snippets Fired (total) | Spell Corrections (total) | History Sentences | Active Snippets
4. **Footer** — "Reset Stats" button (calls `UsageStatsManager.shared.resetStats()` then refreshes)

Menu entry: "Dashboard..." placed above "Settings..." in the NSMenu, with key equivalent "d".
</context>

<read_first>
- TypeFlow/UI/MenuBarManager.swift — read full file to understand `openSettings()` pattern, `settingsWindow` property, and `setupMenu()` NSMenu construction — Dashboard must mirror this exactly
- TypeFlow/Services/UsageStatsManager.swift — read to understand `AllTimeStats`, `DayStats`, `getDailyStats(days:)`, `getAllTimeStats()`, `resetStats()` API
- TypeFlow/Services/TypingHistoryManager.swift — read to understand `getHistory().count` for sentence count
- TypeFlow/Services/SettingsManager.swift — read to understand `getSnippets().count` for active snippet count
</read_first>

<action>
**Step 1: Create `TypeFlow/UI/DashboardView.swift`**

```swift
import SwiftUI
import Charts

struct DashboardView: View {
    @State private var allTime: AllTimeStats = UsageStatsManager.shared.getAllTimeStats()
    @State private var dailyData: [DayStats] = UsageStatsManager.shared.getDailyStats(days: 30)
    @State private var showResetConfirm = false

    private var historyCount: Int { TypingHistoryManager.shared.getHistory().count }
    private var snippetCount: Int { SettingsManager.shared.getSnippets().count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // MARK: Header
                Text("Productivity Dashboard")
                    .font(.largeTitle)
                    .bold()
                    .padding(.top, 4)

                // MARK: Top Stats Cards
                HStack(spacing: 16) {
                    StatCard(value: "\(allTime.totalCompletionsAccepted)",
                             label: "Completions\nAccepted",
                             icon: "checkmark.circle.fill",
                             color: .green)
                    StatCard(value: "\(allTime.wordsSaved)",
                             label: "Words\nSaved",
                             icon: "text.word.spacing",
                             color: .blue)
                    StatCard(value: "\(allTime.totalCharactersSaved)",
                             label: "Characters\nSaved",
                             icon: "keyboard.fill",
                             color: .purple)
                    StatCard(value: String(format: "%.0f%%", allTime.acceptanceRate),
                             label: "Acceptance\nRate",
                             icon: "percent",
                             color: .orange)
                }

                // MARK: 30-Day Chart
                VStack(alignment: .leading, spacing: 8) {
                    Text("Completions Accepted — Last 30 Days")
                        .font(.headline)
                    Chart(dailyData, id: \.date) { day in
                        BarMark(
                            x: .value("Day", day.date),
                            y: .value("Accepted", day.completionsAccepted)
                        )
                        .foregroundStyle(Color.blue.gradient)
                        .cornerRadius(3)
                    }
                    .frame(height: 160)
                    .chartXAxis {
                        AxisMarks(values: .stride(by: 7)) { value in
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)

                // MARK: Secondary Stats
                HStack(spacing: 16) {
                    SecondaryStatRow(icon: "text.badge.plus", label: "Snippets Fired",
                                    value: "\(allTime.totalSnippetsFired)")
                    SecondaryStatRow(icon: "checkmark.rectangle", label: "Spell Corrections",
                                    value: "\(allTime.totalSpellCorrections)")
                    SecondaryStatRow(icon: "clock.arrow.circlepath", label: "Sentences Logged",
                                    value: "\(historyCount)")
                    SecondaryStatRow(icon: "square.stack", label: "Active Snippets",
                                    value: "\(snippetCount)")
                }

                // MARK: Footer
                HStack {
                    Spacer()
                    Button(role: .destructive) {
                        showResetConfirm = true
                    } label: {
                        Label("Reset Stats", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 8)

            }
            .padding(24)
        }
        .frame(width: 700, height: 520)
        .confirmationDialog("Reset all usage statistics?",
                            isPresented: $showResetConfirm,
                            titleVisibility: .visible) {
            Button("Reset", role: .destructive) {
                UsageStatsManager.shared.resetStats()
                allTime = UsageStatsManager.shared.getAllTimeStats()
                dailyData = UsageStatsManager.shared.getDailyStats(days: 30)
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            allTime = UsageStatsManager.shared.getAllTimeStats()
            dailyData = UsageStatsManager.shared.getDailyStats(days: 30)
        }
    }
}

// MARK: - Subviews

struct StatCard: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Spacer()
            }
            Text(value)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct SecondaryStatRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Text(value)
                .font(.title3)
                .bold()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}
```

**Step 2: Update `TypeFlow/UI/MenuBarManager.swift`**

Add `var dashboardWindow: NSWindow?` property alongside `var settingsWindow: NSWindow?`:
```swift
var dashboardWindow: NSWindow?
```

Add `openDashboard()` method immediately after the closing brace of `openSettings()`:
```swift
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
```

In `setupMenu()`, insert the Dashboard menu item before the Settings item. Find:
```swift
menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
```
And prepend before it:
```swift
menu.addItem(NSMenuItem(title: "Dashboard...", action: #selector(openDashboard), keyEquivalent: "d"))
```
</action>

<acceptance_criteria>
- `TypeFlow/UI/DashboardView.swift` exists and contains `struct DashboardView`, `struct StatCard`, `struct SecondaryStatRow`
- `DashboardView.swift` contains `import Charts`
- `DashboardView.swift` contains `BarMark(`
- `DashboardView.swift` contains `UsageStatsManager.shared.getAllTimeStats()`
- `DashboardView.swift` contains `UsageStatsManager.shared.getDailyStats(days: 30)`
- `DashboardView.swift` contains `UsageStatsManager.shared.resetStats()`
- `MenuBarManager.swift` contains `var dashboardWindow: NSWindow?`
- `MenuBarManager.swift` contains `func openDashboard()`
- `MenuBarManager.swift` contains `NSMenuItem(title: "Dashboard..."` 
- `xcodebuild -scheme TypeFlow build` succeeds with no errors
</acceptance_criteria>

---

## Verification

```bash
# Build check
xcodebuild -scheme TypeFlow build -destination 'platform=macOS' 2>&1 | tail -5

# File existence
ls TypeFlow/Services/UsageStatsManager.swift
ls TypeFlow/UI/DashboardView.swift

# Key content checks
grep -c "recordCompletionShown\|recordCompletionAccepted\|recordSnippetFired\|recordSpellCorrection" TypeFlow/Services/CompletionManager.swift
# Expected: 4

grep "Dashboard\.\.\." TypeFlow/UI/MenuBarManager.swift
# Expected: NSMenuItem(title: "Dashboard..."

grep "import Charts" TypeFlow/UI/DashboardView.swift
# Expected: import Charts
```

## must_haves
- Stats increment correctly when completions are accepted (all 4 instrumentation sites fire)
- Dashboard window opens from menu bar with correct title "TypeFlow Dashboard"
- 30-day bar chart renders (empty bars for days with 0 completions are acceptable)
- All-time stat cards display correct values from `UsageStatsManager`
- Reset Stats clears all counters and refreshes the view
- Build succeeds with no compiler errors
