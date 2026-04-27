import SwiftUI

struct StatCard: View {
    let stats: [CardData.Stat]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(stats) { stat in
                VStack(alignment: .leading, spacing: 2) {
                    Text(stat.label)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.textSecondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Text(stat.value)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    if let comparison = stat.comparison {
                        Text(comparison)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .padding(16)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    static func from(rows: [[String: Any?]]) -> StatCard {
        guard let first = rows.first else { return StatCard(stats: []) }
        let stats = first.keys.sorted().map { key in
            CardData.Stat(
                label: key.replacingOccurrences(of: "_", with: " ").capitalized,
                value: CardData.string(from: first, key: key),
                comparison: nil
            )
        }
        return StatCard(stats: stats)
    }
}
