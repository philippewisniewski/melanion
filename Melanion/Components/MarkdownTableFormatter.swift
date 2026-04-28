import Foundation

enum MarkdownTableFormatter {

    /// Format an array of query result rows into a GFM Markdown table string.
    /// Returns an empty string if rows is empty.
    static func format(_ rows: [[String: Any?]]) -> String {
        guard let first = rows.first else { return "" }
        let columns = first.keys.sorted()

        var lines: [String] = []
        // Header row
        lines.append("| " + columns.map { formatHeader($0) }.joined(separator: " | ") + " |")
        // Separator
        lines.append("| " + columns.map { _ in "---" }.joined(separator: " | ") + " |")
        // Data rows
        for row in rows {
            let cells = columns.map { col -> String in
                guard let rawValue = row[col], let value = rawValue else { return "—" }
                return formatValue(value, column: col)
            }
            lines.append("| " + cells.joined(separator: " | ") + " |")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Header formatting

    private static func formatHeader(_ column: String) -> String {
        column
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    // MARK: - Value formatting

    static func formatValue(_ value: Any, column: String) -> String {
        let col = column.lowercased()

        // Pace columns — integer seconds → MM:SS/km
        if col.contains("pace_seconds") || col.contains("split_seconds") || col.contains("gap_seconds") {
            if let seconds = asInt(value) {
                return formatPace(seconds)
            }
        }

        // Duration columns — seconds → Xh Xm or Xm Xs
        if col.contains("duration_seconds") {
            if let seconds = asInt(value) {
                return formatDuration(seconds)
            }
        }

        // Heart rate columns — append bpm
        if col.contains("heart_rate") || col.contains("_bpm") || col.contains("resting_hr") {
            if let val = asInt(value) { return "\(val) bpm" }
        }

        // Date columns — convert to readable string
        if col.contains("date") {
            if let str = value as? String { return formatDate(str) }
        }

        // Distance — km or mi based on user profile
        if col.contains("distance_km") {
            if let val = asDouble(value) {
                let profile = UserProfile.load()
                if profile.preferredUnits == .miles {
                    return String(format: "%.2f mi", val * 0.621371)
                }
                return String(format: "%.2f km", val)
            }
        }

        // Elevation — append m
        if col.contains("elevation") {
            if let val = asDouble(value) { return String(format: "%.0f m", val) }
        }

        // VO2 max
        if col.contains("vo2_max") {
            if let val = asDouble(value) { return String(format: "%.1f ml/kg/min", val) }
        }

        // Sleep
        if col.contains("sleep_duration") {
            if let val = asDouble(value) { return String(format: "%.1f hrs", val) }
        }

        // Calories
        if col.contains("calorie") {
            if let val = asInt(value) { return "\(val) kcal" }
        }

        // Temperature
        if col.contains("temperature") {
            if let val = asDouble(value) { return String(format: "%.1f °C", val) }
        }

        // HRV
        if col.contains("hrv") {
            if let val = asDouble(value) { return String(format: "%.1f ms", val) }
        }

        // SpO2
        if col.contains("oxygen_saturation") {
            if let val = asDouble(value) { return String(format: "%.1f%%", val) }
        }

        // Default — just stringify
        return "\(value)"
    }

    // MARK: - Date formatting

    private static func formatDate(_ raw: String) -> String {
        let inputFormatter = DateFormatter()
        inputFormatter.locale = Locale(identifier: "en_US_POSIX")
        let date: Date?
        if raw.contains("T") {
            inputFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
            date = inputFormatter.date(from: raw)
        } else {
            inputFormatter.dateFormat = "yyyy-MM-dd"
            date = inputFormatter.date(from: raw)
        }
        guard let d = date else { return raw }
        let out = DateFormatter()
        out.dateFormat = "d MMM yyyy"
        out.locale = Locale(identifier: "en_US_POSIX")
        return out.string(from: d)
    }

    // MARK: - Unit helpers (reusable by card components)

    static func formatPace(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d/km", minutes, seconds)
    }

    static func formatDuration(_ totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m \(secs)s"
        } else {
            return "\(secs)s"
        }
    }

    // MARK: - Type coercion helpers

    static func asInt(_ value: Any) -> Int? {
        if let i = value as? Int { return i }
        if let d = value as? Double { return Int(d) }
        if let s = value as? String { return Int(s) }
        return nil
    }

    static func asDouble(_ value: Any) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let s = value as? String { return Double(s) }
        return nil
    }
}
