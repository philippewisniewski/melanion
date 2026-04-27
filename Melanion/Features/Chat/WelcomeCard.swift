import SwiftUI

struct WelcomeCard: View {
    let data: WelcomeData

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome back")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.8)
                Text("Ready to run?")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
            }

            HStack(spacing: 12) {
                StatPill(label: "Last run", value: data.lastRunDate)
                StatPill(label: "Distance", value: String(format: "%.1f km", data.lastRunDistanceKm))
                StatPill(label: "Pace", value: MarkdownTableFormatter.formatPace(data.lastRunPaceSeconds))
            }

            if data.currentStreak > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(Theme.accent)
                    Text("\(data.currentStreak) day streak")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.textPrimary)
                }
            }

            Text("Ask me anything about your training…")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(20)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

struct StatPill: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
