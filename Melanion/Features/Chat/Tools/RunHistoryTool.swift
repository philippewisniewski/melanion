import Foundation
import FoundationModels

struct RunHistoryTool: Tool {
    let name = "getRunHistory"
    let description = "Fetch running workouts with filtering and sorting"

    @Generable
    struct Arguments {
        @Guide(description: "recent, week, month, year, or all")
        var timeframe: String
        @Guide(description: "Max runs to return", .range(1...20))
        var count: Int
        @Guide(description: "date, pace, distance, duration, or elevation")
        var sortBy: String
    }

    func call(arguments: Arguments) async throws -> String {
        let allWorkouts = try await HealthKitWorkoutFetcher().fetchRunningWorkouts()
        guard !allWorkouts.isEmpty else {
            return "No running workouts found."
        }

        let filtered = filterByTimeframe(allWorkouts, timeframe: arguments.timeframe)
        guard !filtered.isEmpty else {
            return "No runs found for timeframe: \(arguments.timeframe)."
        }

        let sorted = sortWorkouts(filtered, by: arguments.sortBy)
        let limited = Array(sorted.prefix(arguments.count))

        return formatWorkouts(limited, total: filtered.count)
    }

    // MARK: - Filtering

    private func filterByTimeframe(_ workouts: [RunWorkout], timeframe: String) -> [RunWorkout] {
        let cal = Calendar.current
        let now = Date()

        let cutoff: Date?
        switch timeframe.lowercased() {
        case "week":
            cutoff = cal.date(byAdding: .day, value: -7, to: now)
        case "month":
            cutoff = cal.date(byAdding: .month, value: -1, to: now)
        case "year":
            cutoff = cal.date(byAdding: .year, value: -1, to: now)
        case "all":
            cutoff = nil
        default:
            cutoff = cal.date(byAdding: .month, value: -1, to: now)
        }

        guard let cutoff else { return workouts }
        return workouts.filter { $0.startedAt >= cutoff }
    }

    // MARK: - Sorting

    private func sortWorkouts(_ workouts: [RunWorkout], by criterion: String) -> [RunWorkout] {
        switch criterion.lowercased() {
        case "pace":
            return workouts.sorted { $0.paceSeconds < $1.paceSeconds }
        case "distance":
            return workouts.sorted { $0.distanceKm > $1.distanceKm }
        case "duration":
            return workouts.sorted { $0.durationSeconds > $1.durationSeconds }
        case "elevation":
            return workouts.sorted { ($0.elevationGainMetres ?? 0) > ($1.elevationGainMetres ?? 0) }
        default:
            return workouts.sorted { $0.startedAt > $1.startedAt }
        }
    }

    // MARK: - Formatting

    private func formatWorkouts(_ workouts: [RunWorkout], total: Int) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "d MMM"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        var lines: [String] = ["\(total) runs in period. Showing \(workouts.count):"]
        for w in workouts {
            var parts = [
                dateFormatter.string(from: w.startedAt),
                String(format: "%.1fkm", w.distanceKm),
                formatPace(w.paceSeconds),
                formatDuration(w.durationSeconds)
            ]
            if let hr = w.heartRateAvgBpm { parts.append("\(hr)bpm") }
            if let cal = w.activeCaloriesKcal { parts.append("\(cal)kcal") }
            if let elev = w.elevationGainMetres, elev > 0 {
                parts.append(String(format: "%.0fm gain", elev))
            }
            if let cadence = w.cadenceStepsPerMin { parts.append("\(cadence)spm") }
            lines.append("- " + parts.joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }

    private func formatPace(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d/km", minutes, seconds)
    }

    private func formatDuration(_ totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(secs)s" }
        return "\(secs)s"
    }
}
