import Foundation
import FoundationModels

struct TrainingTrendsTool: Tool {
    let name = "getTrainingTrends"
    let description = "Compute training trends and totals — pace, distance, volume, frequency, VO2 max, resting HR, calories, and streaks"

    @Generable
    struct Arguments {
        @Guide(description: "week, month, season, or all")
        var period: String
        @Guide(description: "pace, distance, volume, frequency, calories, vo2max, hr, rhr, or streak")
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
        case "calories":
            return caloriesSummary(allWorkouts, period: arguments.period)
        case "vo2max":
            return await vo2maxTrend(period: arguments.period)
        case "hr":
            return hrTrend(allWorkouts, period: arguments.period)
        case "rhr":
            return await restingHRTrend(period: arguments.period)
        default:
            return generalSummary(allWorkouts, period: arguments.period)
        }
    }

    // MARK: - Pace trend

    private func paceTrend(_ workouts: [RunWorkout], period: String) -> String {
        let buckets = bucketize(workouts, period: period)
        var lines: [String] = ["Pace trend by \(period):"]
        for (label, runs) in buckets.suffix(8) {
            let avgPace = weightedAveragePace(runs)
            lines.append("- \(label): \(formatPace(avgPace)) avg (\(runs.count) runs)")
        }
        if buckets.count > 1, let first = buckets.first, let last = buckets.last {
            let firstPace = weightedAveragePace(first.1)
            let lastPace = weightedAveragePace(last.1)
            let diff = lastPace - firstPace
            let label = diff < 0 ? "faster" : diff > 0 ? "slower" : "unchanged"
            lines.append("Change: \(formatPace(firstPace)) → \(formatPace(lastPace)) (\(abs(diff))s/km \(label))")
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
        let weeks: Int
        if let first = workouts.first, let last = workouts.last {
            weeks = max(1, Calendar.current.dateComponents([.weekOfYear], from: last.startedAt, to: first.startedAt).weekOfYear ?? 1)
        } else {
            weeks = 1
        }
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
        var lines: [String] = ["Exercise heart rate trend by \(period):"]
        for (label, runs) in buckets.suffix(8) {
            let avgHR = runs.compactMap(\.heartRateAvgBpm).reduce(0, +) / max(runs.count, 1)
            let maxHR = runs.compactMap(\.heartRateMaxBpm).max() ?? 0
            lines.append("- \(label): \(avgHR)bpm avg, \(maxHR)bpm max (\(runs.count) runs)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Calories

    private func caloriesSummary(_ workouts: [RunWorkout], period: String) -> String {
        let filtered = filterByPeriod(workouts, period: period)
        let withCals = filtered.filter { $0.activeCaloriesKcal != nil }
        guard !withCals.isEmpty else {
            return "No calorie data available. Calorie tracking requires Apple Watch or a device that records active energy."
        }
        let total = withCals.compactMap(\.activeCaloriesKcal).reduce(0, +)
        let avg = total / withCals.count
        return "\(withCals.count) runs with calorie data. Total: \(total)kcal. Average: \(avg)kcal/run."
    }

    // MARK: - VO2 max trend

    private func vo2maxTrend(period: String) async -> String {
        let window = trendWindow(for: period)
        let samples = await HealthKitRecoveryFetcher().fetchVO2MaxSamples(in: window)
        guard samples.count >= 2 else {
            if let single = samples.first {
                return "VO2 max: \(String(format: "%.1f", single)) ml/kg/min. Not enough data for trend."
            }
            return "No VO2 max data available."
        }

        let quarter = max(1, samples.count / 4)
        let startAvg = samples.prefix(quarter).reduce(0, +) / Double(quarter)
        let endAvg = samples.suffix(quarter).reduce(0, +) / Double(quarter)
        let change = endAvg - startAvg
        let direction = change > 0 ? "increased" : change < 0 ? "decreased" : "unchanged"

        return "VO2 max \(direction) by \(String(format: "%.1f", abs(change))) ml/kg/min over \(period). Current: \(String(format: "%.1f", endAvg)) ml/kg/min. Start: \(String(format: "%.1f", startAvg)) ml/kg/min. \(samples.count) samples."
    }

    // MARK: - Resting HR trend

    private func restingHRTrend(period: String) async -> String {
        let window = trendWindow(for: period)
        let samples = await HealthKitRecoveryFetcher().fetchRestingHRSamples(in: window)
        guard samples.count >= 2 else {
            if let single = samples.first {
                return "Resting HR: \(Int(single))bpm. Not enough data for trend."
            }
            return "No resting heart rate data available."
        }

        let quarter = max(1, samples.count / 4)
        let startAvg = samples.prefix(quarter).reduce(0, +) / Double(quarter)
        let endAvg = samples.suffix(quarter).reduce(0, +) / Double(quarter)
        let change = endAvg - startAvg
        let direction = change > 0 ? "increased" : change < 0 ? "decreased" : "stable"

        return "Resting HR \(direction) by \(String(format: "%.0f", abs(change)))bpm over \(period). Current avg: \(Int(endAvg))bpm. Start avg: \(Int(startAvg))bpm. \(samples.count) samples."
    }

    // MARK: - General summary

    private func generalSummary(_ workouts: [RunWorkout], period: String) -> String {
        let filtered = filterByPeriod(workouts, period: period)
        guard !filtered.isEmpty else { return "No runs in this period." }

        let totalKm = filtered.map(\.distanceKm).reduce(0, +)
        let avgPace = weightedAveragePace(filtered)
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
            cutoff = cal.dateInterval(of: .weekOfYear, for: now)?.start
        case "month":
            cutoff = cal.dateInterval(of: .month, for: now)?.start
        case "season":
            cutoff = cal.date(byAdding: .month, value: -3, to: now)
        case "all":
            cutoff = nil
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

    private func weightedAveragePace(_ runs: [RunWorkout]) -> Int {
        let totalDuration = runs.map(\.durationSeconds).reduce(0, +)
        let totalDistance = runs.map(\.distanceKm).reduce(0, +)
        guard totalDistance > 0 else { return 0 }
        return Int(Double(totalDuration) / totalDistance)
    }

    private func trendWindow(for period: String) -> DateInterval {
        let cal = Calendar.current
        let now = Date()
        let start: Date
        switch period.lowercased() {
        case "week":
            start = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        case "month":
            start = cal.dateInterval(of: .month, for: now)?.start ?? now
        case "season":
            start = cal.date(byAdding: .month, value: -3, to: now) ?? now
        case "all":
            start = cal.date(byAdding: .year, value: -5, to: now) ?? now
        default:
            start = cal.date(byAdding: .month, value: -3, to: now) ?? now
        }
        return DateInterval(start: start, end: now)
    }

    private func formatPace(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d/km", minutes, seconds)
    }
}
