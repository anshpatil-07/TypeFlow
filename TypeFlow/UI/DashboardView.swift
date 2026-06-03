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
                        AxisMarks(values: .stride(by: 7)) { _ in
                            AxisValueLabel()
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
