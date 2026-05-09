import Foundation
import FoundationModels

struct RecoveryTool: Tool {
    let name = "getRecoveryData"
    let description = "Fetch recovery metrics — sleep, HRV, resting HR, VO2 max, and respiratory data around a run"

    @Generable
    struct Arguments {
        @Guide(description: "ISO date string or 'latest'")
        var runDate: String
    }

    func call(arguments: Arguments) async throws -> String {
        let workouts = try await HealthKitWorkoutFetcher().fetchRunningWorkouts()
        guard let firstWorkout = workouts.first else {
            return "No running workouts found."
        }

        let targetDate: Date
        if arguments.runDate.lowercased() == "latest" {
            targetDate = firstWorkout.startedAt
        } else {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            targetDate = formatter.date(from: arguments.runDate) ?? firstWorkout.startedAt
        }

        let bundles = await HealthKitRecoveryFetcher().fetchRecovery(for: [targetDate])
        guard let bundle = bundles.first else {
            return "No recovery data available for \(formatDate(targetDate))."
        }

        return formatBundle(bundle, workouts: workouts)
    }

    // MARK: - Formatting

    private func formatBundle(_ bundle: RecoveryBundle, workouts: [RunWorkout]) -> String {
        let dateStr = formatDate(bundle.runStartedAt)
        let run = workouts.first { Calendar.current.isDate($0.startedAt, inSameDayAs: bundle.runStartedAt) }

        var lines: [String] = ["Recovery data for run on \(dateStr):"]

        if let run {
            lines.append("Run: \(String(format: "%.1fkm", run.distanceKm)), \(formatPace(run.paceSeconds))")
        }

        lines.append("")
        lines.append(formatPeriod("Night before", bundle.nightBefore))
        lines.append(formatPeriod("Run day", bundle.runDay))
        lines.append(formatPeriod("Day after", bundle.dayAfter))

        return lines.joined(separator: "\n")
    }

    private func formatPeriod(_ label: String, _ m: RecoveryMetrics) -> String {
        var parts: [String] = []
        if let sleep = m.sleepDurationHours { parts.append(String(format: "%.1fh sleep", sleep)) }
        if let hrv = m.hrvMs { parts.append(String(format: "%.0fms HRV", hrv)) }
        if let rhr = m.restingHeartRateBpm { parts.append("\(rhr)bpm RHR") }
        if let vo2 = m.vo2MaxMlKgMin { parts.append(String(format: "%.1f VO2max", vo2)) }
        if let hrr = m.heartRateRecoveryBpm { parts.append("\(hrr)bpm HR recovery") }
        if let resp = m.respiratoryRate { parts.append(String(format: "%.1f breaths/min", resp)) }
        if let temp = m.wristTemperatureC { parts.append(String(format: "%.1f°C wrist temp", temp)) }
        if let spo2 = m.oxygenSaturationPct { parts.append(String(format: "%.1f%% SpO2", spo2)) }

        if parts.isEmpty { return "\(label): No data" }
        return "\(label): " + parts.joined(separator: ", ")
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    private func formatPace(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d/km", minutes, seconds)
    }
}
