import Foundation

enum CardData {
    struct Stat: Identifiable, Sendable {
        let id = UUID()
        let label: String
        let value: String
        let comparison: String?
    }

    struct RankedRow: Identifiable, Sendable {
        let id = UUID()
        let rank: Int
        let label: String
        let value: String
    }

    struct TrendPoint: Identifiable, Sendable {
        let id = UUID()
        let label: String
        let value: Double
        let displayValue: String
    }

    struct DetailRow: Identifiable, Sendable {
        let id = UUID()
        let label: String
        let value: String
    }
}

// MARK: - Extraction helpers

extension CardData {
    static func string(from row: [String: Any?], key: String) -> String {
        guard let raw = row[key], let val = raw else { return "—" }
        return MarkdownTableFormatter.formatValue(val, column: key)
    }

    static func double(from row: [String: Any?], key: String) -> Double? {
        guard let raw = row[key], let val = raw else { return nil }
        return MarkdownTableFormatter.asDouble(val)
    }
}
