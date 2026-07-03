# Phase 13: Productivity Dashboard — Research

**Researched:** 2026-06-03
**Phase:** 13 — Productivity Dashboard

---

## 1. Meaningful Dashboard Metrics

The most useful and non-intrusive stats for a typing assistant dashboard:

### Core Counters (high-value, easy to instrument)
| Metric | Source | What it shows |
|--------|--------|---------------|
| Completions shown | CompletionManager (new counter) | AI activity level |
| Completions accepted | CompletionManager `acceptCompletion` (new counter) | Acceptance rate |
| Acceptance rate (%) | accepted / shown | Quality signal |
| Characters saved | accepted completions' `.count` | Time saved proxy |
| Words saved | characters saved / 5 (avg word length) | More relatable unit |
| Snippets fired | CompletionManager snippet branch (new counter) | Snippet utility |
| Spell corrections | CompletionManager spell branch (new counter) | Auto-correct value |

### Per-Day Aggregation
- Stats stored as daily buckets: `[YYYY-MM-DD: DayStats]`
- Rolling 30-day window visible in the chart
- All-time totals computed from aggregated daily data

### Additional Useful Metrics (Tier 2)
- Top used snippets (from existing SettingsManager snippets + fire counter)
- Typing session count (proxy from AccessibilityMonitor app changes)
- Typing history sentence count (already available from TypingHistoryManager)

---

## 2. SwiftUI Dashboard Patterns for macOS 14+

### Charts Framework (Available macOS 13+)
- `import Charts` — native Apple framework, no dependencies
- `BarChart`, `LineMark`, `AreaMark` all supported
- Best for 30-day bar chart of completions accepted
- `Chart { ForEach(days) { BarMark(x: .value("Day", $0.date), y: .value("Completions", $0.accepted)) } }`

### Window Strategy: NSWindow (same pattern as Settings)
The existing `MenuBarManager` already opens Settings via a raw `NSWindow` + `NSHostingView`. The dashboard should follow the **exact same pattern**:
```swift
var dashboardWindow: NSWindow?

@objc func openDashboard() {
    if dashboardWindow == nil {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = "TypeFlow Dashboard"
        window.isReleasedWhenClosed = false
        window.center()
        dashboardWindow = window
    }
    dashboardWindow?.contentView = NSHostingView(rootView: DashboardView())
    NSApp.activate(ignoringOtherApps: true)
    dashboardWindow?.makeKeyAndOrderFront(nil)
}
```

### Menu Entry
Add `NSMenuItem(title: "Dashboard...", action: #selector(openDashboard), keyEquivalent: "d")` to the NSMenu in `setupMenu()`, above Settings.

---

## 3. Stats Persistence Strategy

### Approach: JSON file in Application Support (consistent with existing pattern)
The app already stores `history.enc` and `snippets.enc` in `~/Library/Application Support/TypeFlow/`.

For stats, **no encryption needed** — these are aggregate counters, not personal content:
- File: `~/Library/Application Support/TypeFlow/stats.json`
- Format: `[String: DayStats]` where key is `"YYYY-MM-DD"`
- `DayStats` struct: `{ date, completionsShown, completionsAccepted, charactersSaved, snippetsFired, spellCorrections }`
- Save: debounced write after every event (or batch on app quit)
- Load: once at init, kept in memory

### `UsageStatsManager` — new singleton service
```swift
class UsageStatsManager {
    static let shared = UsageStatsManager()
    func recordCompletionShown()
    func recordCompletionAccepted(charactersSaved: Int)
    func recordSnippetFired()
    func recordSpellCorrection()
    func getDailyStats(days: Int) -> [DayStats]
    func getAllTimeStats() -> AllTimeStats
}
```

### Instrumentation touch points (minimal surgical edits):
1. `CompletionManager.showCompletion()` → `UsageStatsManager.shared.recordCompletionShown()`
2. `CompletionManager.acceptCompletion()` → `UsageStatsManager.shared.recordCompletionAccepted(charactersSaved: completion.count)`
3. `CompletionManager` snippet branch → `UsageStatsManager.shared.recordSnippetFired()`
4. `CompletionManager` spell correction branch → `UsageStatsManager.shared.recordSpellCorrection()`

---

## 4. Existing TypeFlow Data vs New Instrumentation

### Already available (no changes needed)
- Typing history sentence count → `TypingHistoryManager.shared.getHistory().count`
- Suggested snippets count → `TypingHistoryManager.shared.getSuggestedSnippets().count`
- Active snippets count → `SettingsManager.shared.getSnippets().count`
- Active model name → `SettingsManager.shared.activeModelId`

### Needs new instrumentation (4 touch points in CompletionManager)
- Completions shown count → new counter
- Completions accepted count + chars saved → new counter at acceptance point
- Snippets fired → new counter at snippet branch
- Spell corrections → new counter at spell correction branch

### Does NOT need (avoid scope creep)
- Per-app breakdown (complex, not MVP)
- Latency histograms (complex, not valuable to user)
- Network/cloud stats (none — all on-device)

---

## 5. Privacy Considerations

- All stats are aggregate counters — no raw text is stored in stats file
- Stats file is plaintext JSON (counts, dates) — no personal content
- Consistent with TypeFlow's privacy model: typing history already encrypted, stats are just numbers
- No network calls — stats never leave device
- User can clear stats (add "Reset Stats" button in dashboard)

---

## 6. Opening Dashboard Window from Menu Bar

The `MenuBarManager.swift` class owns the `NSStatusItem` and `NSMenu`. The pattern for opening a secondary window is already established by `openSettings()`. Simply:
1. Add `var dashboardWindow: NSWindow?` property alongside `settingsWindow`
2. Add `@objc func openDashboard()` mirroring `openSettings()` but hosting `DashboardView()`
3. Add menu item in `setupMenu()`: `NSMenuItem(title: "Dashboard...", action: #selector(openDashboard), keyEquivalent: "d")`

---

## Recommended Implementation Plan

### Wave 1 — Stats Infrastructure (no UI yet)
1. Create `UsageStatsManager.swift` with `DayStats`/`AllTimeStats` structs, JSON persistence to `stats.json`, and the 4 record methods
2. Add 4 instrumentation call sites in `CompletionManager.swift`

### Wave 2 — Dashboard UI (depends on Wave 1)
3. Create `DashboardView.swift` in `TypeFlow/UI/` with:
   - Header: all-time totals (completions accepted, characters saved, acceptance rate %)
   - 30-day bar chart using `Charts` framework
   - Snippet stats row (active snippets, snippets fired today)
   - History stats row (sentences logged, model active)
   - Reset Stats button
4. Wire `MenuBarManager.swift`:
   - Add `dashboardWindow` property
   - Add `openDashboard()` method
   - Add "Dashboard..." menu item

### Wave 3 — Verification
5. Build succeeds, Dashboard opens, stats increment in real-time, 30-day chart renders

---

## Validation Architecture

### Automated checks
- `xcodebuild` passes — `import Charts` compiles (macOS 13+ ✓)
- `UsageStatsManager` encodes/decodes `DayStats` correctly
- `stats.json` file created in Application Support

### Manual checks
- Menu bar shows "Dashboard..." item
- Dashboard window opens on click
- All-time counters increment when completion is accepted (fire, check dashboard)
- 30-day chart renders bars for days with activity
- Reset Stats clears all counters

---

## RESEARCH COMPLETE
