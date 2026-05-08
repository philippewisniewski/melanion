import Foundation
import FoundationModels

struct TrainingTrendsTool: Tool {
    let name = "getTrainingTrends"
    let description = "Compute training trends and aggregates over time"

    @Generable
    struct Arguments {
        @Guide(description: "week, month, or season")
        var period: String
        @Guide(description: "pace, distance, volume, frequency, vo2max, hr, or streak")
        var metric: String
    }

    func call(arguments: Arguments) async throws -> String {
        let allWorkouts = try await HealthKitWorkoutFetcher().fetchRunningWorkouts()
        guard !allWorkouts.isEmpty else {
            return "No running workouts found."
        }

        switch arguments.metric.lowercased() {
        case "pace":
            return paceTrend(allWorkouts, period: arguments.period)
        case "distance":
            return distanceTrend(allWorkouts, period: arguments.period)
        case "volume":
            return volumeTrend(allWorkouts, period: arguments.period)
        case "frequency":
            return frequencyTrend(allWorkouts, period: arguments.period)
        case "streak":
            return streakInfo(allWorkouts)
        case "hr":
            return hrTrend(allWorkouts, period: arguments.period)
        default:
            return generalSummary(allWorkouts, period: arguments.period)
        }
    }

    // MARK: - Pace trend

    private func paceTrend(_ workouts: [RunWorkout], period: String) -> String {
        let buckets = bucketize(workouts, period: period)
        var lines: [String] = ["Pace trend by \(period):"]
        for (label, runs) in buckets.suffix(8) {
            let avgPace = runs.map(\.paceSeconds).reduce(0, +) / max(runs.count, 1)
            lines.append("- \(label): \(formatPace(avgPace)) avg (\(runs.count) runs)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Distance trend

    private func distanceTrend(_ workouts: [RunWorkout], period: String) -> String {
        let buckets = bucketize(workouts, period: period)
        var lines: [String] = ["Distance trend by \(period):"]
        for (label, runs) in buckets.suffix(8) {
            let avg = runs.map(\.distanceKm).reduce(0, +) / max(Double(runs.count), 1)
            let total = runs.map(\.distanceKm).reduce(0, +)
            lines.append("- \(label): \(String(format: "%.1fkm", total)) total, \(String(format: "%.1fkm", avg)) avg (\(runs.count) runs)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Volume trend

    private func volumeTrend(_ workouts: [RunWorkout], period: String) -> String {
        let buckets = bucketize(workouts, period: period)
        var lines: [String] = ["Training volume by \(period):"]
        for (label, runs) in buckets.suffix(8) {
            let totalKm = runs.map(\.distanceKm).reduce(0, +)
            let totalMin = runs.map(\.durationSeconds).reduce(0, +) / 60
            lines.append("- \(label): \(String(format: "%.1fkm", totalKm)), \(totalMin)min, \(runs.count) runs")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Frequency trend

    private func frequencyTrend(_ workouts: [RunWorkout], period: String) -> String {
        let buckets = bucketize(workouts, period: period)
        var lines: [String] = ["Run frequency by \(period):"]
        for (label, runs) in buckets.suffix(8) {
            lines.append("- \(label): \(runs.count) runs")
        }
        let total = workouts.count
        let weeks = max(1, Calendar.current.dateComponents([.weekOfYear], from: workouts.last!.startedAt, to: workouts.first!.startedAt).weekOfYear ?? 1)
        lines.append("Overall: \(total) runs over \(weeks) weeks (\(String(format: "%.1f", Double(total) / Double(weeks))) runs/week)")
        return lines.joined(separator: "\n")
    }

    // MARK: - Streak

    private func streakInfo(_ workouts: [RunWorkout]) -> String {
        let cal = Calendar.current
        let runDays = Set(workouts.map { cal.startOfDay(for: $0.startedAt) }).sorted(by: >)
        guard let latest = runDays.first else { return "No runs found." }

        var currentStreak = 1
        for i in 1..<runDays.count {
            let expected = cal.date(byAdding: .day, value: -i, to: latest)!
            if cal.isDate(runDays[i], inSameDayAs: expected) {
                currentStreak += 1
            } else {
                break
            }
        }

        var longestStreak = 1
        var tempStreak = 1
        for i in 1..<runDays.count {
            let diff = cal.dateComponents([.day], from: runDays[i], to: runDays[i - 1]).day ?? 0
            if diff == 1 {
                tempStreak += 1
                longestStreak = max(longestStreak, tempStreak)
            } else {
                tempStreak = 1
            }
        }

        return "Current streak: \(currentStreak) day(s). Longest streak: \(longestStreak) day(s). Total runs: \(workouts.count)."
    }

    // MARK: - HR trend

    private func hrTrend(_ workouts: [RunWorkout], period: String) -> String {
        let withHR = workouts.filter { $0.heartRateAvgBpm != nil }
        guard !withHR.isEmpty else { return "No heart rate data available." }

        let buckets = bucketize(withHR, period: period)
        var lines: [String] = ["Heart rate trend by \(period):"]
        for (label, runs) in buckets.suffix(8) {
            let avgHR = runs.compactMap(\.heartRateAvgBpm).reduce(0, +) / max(runs.count, 1)
            let maxHR = runs.compactMap(\.heartRateMaxBpm).max() ?? 0
            lines.append("- \(label): \(avgHR)bpm avg, \(maxHR)bpm max (\(runs.count) runs)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - General summary

    private func generalSummary(_ workouts: [RunWorkout], period: String) -> String {
        let filtered = filterByPeriod(workouts, period: period)
        guard !filtered.isEmpty else { return "No runs in this period." }

        let totalKm = filtered.map(\.distanceKm).reduce(0, +)
        let avgPace = filtered.map(\.paceSeconds).reduce(0, +) / filtered.count
        let avgDist = totalKm / Double(filtered.count)
        let avgHR = filtered.compactMap(\.heartRateAvgBpm)
        let hrStr = avgHR.isEmpty ? "" : ", \(avgHR.reduce(0, +) / avgHR.count)bpm avg HR"

        return "\(filtered.count) runs, \(String(format: "%.1fkm", totalKm)) total, \(String(format: "%.1fkm", avgDist)) avg distance, \(formatPace(avgPace)) avg pace\(hrStr)."
    }

    // MARK: - Helpers

    private func filterByPeriod(_ workouts: [RunWorkout], period: String) -> [RunWorkout] {
        let cal = Calendar.current
        let now = Date()
        let cutoff: Date?
        switch period.lowercased() {
        case "week":
            cutoff = cal.date(byAdding: .day, value: -7, to: now)
        case "month":
            cutoff = cal.date(byAdding: .month, value: -1, to: now)
        case "season":
            cutoff = cal.date(byAdding: .month, value: -3, to: now)
        default:
            cutoff = cal.date(byAdding: .month, value: -1, to: now)
        }
        guard let cutoff else { return workouts }
        return workouts.filter { $0.startedAt >= cutoff }
    }

    private func bucketize(_ workouts: [RunWorkout], period: String) -> [(String, [RunWorkout])] {
        let cal = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        let keyForWorkout: (RunWorkout) -> String
        switch period.lowercased() {
        case "week":
            formatter.dateFormat = "d MMM"
            keyForWorkout = { w in
                let weekStart = cal.dateInterval(of: .weekOfYear, for: w.startedAt)?.start ?? w.startedAt
                return "w/c " + formatter.string(from: weekStart)
            }
        case "season":
            keyForWorkout = { w in
                let month = cal.component(.month, from: w.startedAt)
                let year = cal.component(.year, from: w.startedAt)
                switch month {
                case 3...5: return "Spring \(year)"
                case 6...8: return "Summer \(year)"
                case 9...11: return "Autumn \(year)"
                default: return "Winter \(year)"
                }
            }
        default:
            formatter.dateFormat = "MMM yyyy"
            keyForWorkout = { w in formatter.string(from: w.startedAt) }
        }

        var dict: [String: [RunWorkout]] = [:]
        var order: [String] = []
        for w in workouts.sorted(by: { $0.startedAt < $1.startedAt }) {
            let key = keyForWorkout(w)
            if dict[key] == nil { order.append(key) }
            dict[key, default: []].append(w)
        }
        return order.map { ($0, dict[$0]!) }
    }

    private func formatPace(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d/km", minutes, seconds)
    }
}
