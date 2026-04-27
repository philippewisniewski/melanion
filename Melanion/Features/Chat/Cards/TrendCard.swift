import SwiftUI
import Charts

struct TrendCard: View {
    let points: [CardData.TrendPoint]
    let yAxisLabel: String
    let isPaceAxis: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(yAxisLabel)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(Theme.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)

            Chart(points) { point in
                LineMark(
                    x: .value("Label", point.label),
                    y: .value(yAxisLabel, point.value)
                )
                .foregroundStyle(Theme.accent)
                .interpolationMethod(.catmullRom)

                AreaMark(
                    x: .value("Label", point.label),
                    yStart: .value("Base", minValue),
                    yEnd: .value(yAxisLabel, point.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Theme.accent.opacity(0.25), Theme.accent.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisValueLabel()
                        .foregroundStyle(Theme.textSecondary)
                        .font(.system(size: 10))
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    if isPaceAxis, let v = value.as(Double.self) {
                        AxisValueLabel(
                            MarkdownTableFormatter.formatPace(Int(v)),
                            centered: false
                        )
                        .foregroundStyle(Theme.textSecondary)
                        .font(.system(size: 10))
                    } else {
                        AxisValueLabel()
                            .foregroundStyle(Theme.textSecondary)
                            .font(.system(size: 10))
                    }
                }
            }
            .chartYScale(domain: minValue...maxValue)
            .frame(height: 180)
        }
        .padding(16)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var minValue: Double { (points.map(\.value).min() ?? 0) * 0.95 }
    private var maxValue: Double {
        let raw = (points.map(\.value).max() ?? 1) * 1.05
        // chartYScale domain must have positive length — guard against all-zero data
        return raw > minValue ? raw : minValue + 1
    }

    static func from(rows: [[String: Any?]], yAxisLabel: String = "") -> TrendCard {
        let keys = rows.first?.keys.sorted() ?? []
        let xKey = keys.first(where: {
            $0.contains("date") || $0.contains("week") || $0.contains("month")
        }) ?? keys.first ?? ""
        let yKey = keys.first(where: { $0 != xKey }) ?? ""
        let isPace = yKey.contains("pace") || yKey.contains("split")
        let label = yAxisLabel.isEmpty
            ? yKey.replacingOccurrences(of: "_", with: " ").capitalized
            : yAxisLabel

        let points = rows.compactMap { row -> CardData.TrendPoint? in
            guard let val = CardData.double(from: row, key: yKey) else { return nil }
            return CardData.TrendPoint(
                label: CardData.string(from: row, key: xKey),
                value: val,
                displayValue: CardData.string(from: row, key: yKey)
            )
        }
        return TrendCard(points: points, yAxisLabel: label, isPaceAxis: isPace)
    }
}
