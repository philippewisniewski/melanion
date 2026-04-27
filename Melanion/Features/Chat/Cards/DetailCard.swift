import SwiftUI

struct DetailCard: View {
    let rows: [CardData.DetailRow]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                        .lineLimit(1)
                    Text(row.value)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Theme.background)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(12)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    static func from(rows: [[String: Any?]]) -> DetailCard {
        let detailRows = rows.flatMap { row in
            row.keys.sorted().map { key in
                CardData.DetailRow(
                    label: key.replacingOccurrences(of: "_", with: " ").capitalized,
                    value: CardData.string(from: row, key: key)
                )
            }
        }
        return DetailCard(rows: detailRows)
    }
}
