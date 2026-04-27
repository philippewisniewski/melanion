import SwiftUI

struct RankedListCard: View {
    let rows: [CardData.RankedRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.prefix(10).enumerated()), id: \.element.id) { index, row in
                HStack(spacing: 12) {
                    Text("\(row.rank)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 24, alignment: .center)
                    Text(row.label)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text(row.value)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)

                if index < min(rows.count, 10) - 1 {
                    Divider()
                        .background(Theme.background)
                        .padding(.leading, 50)
                }
            }
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    static func from(rows: [[String: Any?]]) -> RankedListCard {
        let ranked = rows.prefix(10).enumerated().map { i, row in
            let keys = row.keys.sorted()
            let labelKey = keys.first(where: {
                $0.contains("date") || $0.contains("name") || $0.contains("pattern") ||
                $0.contains("time") || $0.contains("season")
            }) ?? keys.first ?? ""
            let valueKey = keys.first(where: { $0 != labelKey }) ?? ""
            return CardData.RankedRow(
                rank: i + 1,
                label: CardData.string(from: row, key: labelKey),
                value: CardData.string(from: row, key: valueKey)
            )
        }
        return RankedListCard(rows: Array(ranked))
    }
}
