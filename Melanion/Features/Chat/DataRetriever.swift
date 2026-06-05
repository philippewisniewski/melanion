import Foundation

@MainActor
struct DataRetriever {

    // MARK: - Public API

    func retrieve(for question: String) async -> (data: String, precomputed: String) {
        let workouts = (try? await HealthKitWorkoutFetcher().fetchRunningWorkouts()) ?? []
        let intent = classify(question)
        let data = await formatData(for: intent, workouts: workouts)
        let precomputed = formatPrecomputed(workouts: workouts)
        return (data, precomputed)
    }

    // MARK: - Intent Classification

    private enum Intent {
        case lastRun
        case lastFew(Int)
        case longestRun
        case fastestRun
        case slowestRun
        case averagePace
        case averageDistance
        case calories
        case elevation
        case streaks
        case heartRate
        case cadence
        case recovery
        case trends
        case weeklyMonthly
        case total
        case routes
        case general
    }

    private func classify(_ question: String) -> Intent {
        let q = question.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Most specific intents first — before generic "last run"
        if q.contains("recovery") || q.contains("sleep") || q.contains("hrv") || q.contains("rest") || q.contains("readiness") { return .recovery }
        if q.contains("heart rate") || q.contains("hr ") || q.contains(" bpm") || q.contains("cardio") || q.contains("pulse") { return .heartRate }
        if q.contains("elevation") || q.contains("gain") || q.contains("climb") || q.contains("hill") { return .elevation }
        if q.contains("cadence") || q.contains("spm") || q.contains("stride") || q.contains("step") { return .cadence }
        if (q.contains("calories") || q.contains("kcal") || q.contains("energy") || q.contains("burn")) && !q.contains("recovery") { return .calories }
        if q.contains("streak") || q.contains("consistency") || q.contains("days in a row") { return .streaks }
        if q.contains("route") || q.contains("gpx") || q.contains("map") || q.contains("location") || q.contains("where ") { return .routes }
        if q.contains("trend") || q.contains("overview") || q.contains("summary") || q.contains("progress") || q.contains("improve") || q.contains("change") { return .trends }
        if q.contains("total") || q.contains("all time") || q.contains("ever") || q.contains("overall") || q.contains("lifetime") { return .total }
        if q.contains("week") || q.contains("weekly") || q.contains("month") || q.contains("monthly") || q.contains("volume") || q.contains("frequency") || q.contains("often") { return .weeklyMonthly }

        // Numeric requests before single "last run"
        if let n = extractNumber(after: "last", in: q) { return .lastFew(n) }
        if let n = extractNumber(after: "recent", in: q) { return .lastFew(n) }

        // Pace and distance questions
        if q.contains("average pace") || q.contains("avg pace") || q.contains("typical pace") || q.contains("pacing") { return .averagePace }
        if q.contains("average distance") || q.contains("avg distance") || q.contains("typical distance") { return .averageDistance }
        if q.contains("splits") || q.contains("split") { return .trends }

        // Single-run queries
        if q.contains("longest") || q.contains("furthest") || q.contains("max distance") { return .longestRun }
        if q.contains("fastest") || q.contains("best pace") || q.contains("quickest") { return .fastestRun }
        if q.contains("slowest") || q.contains("easiest") || q.contains("worst pace") { return .slowestRun }

        if q.contains("last run") || q.contains("latest run") || q.contains("most recent") {
            return .lastRun
        }

        return .general
    }

    private func extractNumber(after keyword: String, in text: String) -> Int? {
        guard let range = text.range(of: keyword, options: .backwards) else { return nil }
        let remainder = text[range.upperBound...].trimmingCharacters(in: .whitespaces)
        let words = remainder.split(separator: " ").prefix(2)
        if let first = words.first, let n = Int(first) {
            return min(max(n, 1), 20)
        }
        return nil
    }

    // MARK: - Data Formatting

    private func formatData(for intent: Intent, workouts: [RunWorkout]) async -> String {
        guard !workouts.isEmpty else { return "No runs found." }

        switch intent {
        case .lastRun:
            return "Your most recent run:\n" + formatWorkoutLine(workouts[0])

        case .lastFew(let n):
            let count = min(n, workouts.count)
            let lines = workouts.prefix(count).map(formatWorkoutLine)
            return "Last \(count) run\(count == 1 ? "" : "s"):\n" + lines.joined(separator: "\n")

        case .longestRun, .fastestRun, .slowestRun, .averagePace, .averageDistance, .total:
            return ""

        case .calories:
            let withCals = workouts.filter { $0.activeCaloriesKcal != nil }.prefix(10)
            guard !withCals.isEmpty else { return "" }
            return "Runs with calorie data:\n" + withCals.map(formatWorkoutLine).joined(separator: "\n")

        case .elevation:
            let withElev = workouts
                .filter { $0.elevationGainMetres != nil && $0.elevationGainMetres! > 0 }
                .sorted { ($0.elevationGainMetres ?? 0) > ($1.elevationGainMetres ?? 0) }
                .prefix(10)
            guard !withElev.isEmpty else { return "" }
            return "Top runs by elevation:\n" + withElev.map(formatWorkoutLine).joined(separator: "\n")

        case .streaks:
            let dates = workouts.prefix(20).map { formatDate($0.startedAt) }
            return "Recent run dates: " + dates.joined(separator: ", ")

        case .heartRate:
            let withHR = workouts.filter { $0.heartRateAvgBpm != nil }.prefix(10)
            guard !withHR.isEmpty else { return "" }
            return "Recent runs with heart rate:\n" + withHR.map(formatWorkoutLine).joined(separator: "\n")

        case .cadence:
            let withCadence = workouts.filter { $0.cadenceStepsPerMin != nil }.prefix(10)
            guard !withCadence.isEmpty else { return "" }
            return "Recent runs with cadence:\n" + withCadence.map(formatWorkoutLine).joined(separator: "\n")

        case .recovery:
            return await formatRecovery(workouts[0].startedAt)

        case .trends, .weeklyMonthly:
            return formatTrends(workouts)

        case .routes:
            return "Route data: Multiple GPX route files available on device."

        case .general:
            return await formatGeneralSummary(workouts)
        }
    }

    private func formatPrecomputed(workouts: [RunWorkout]) -> String {
        let valid = workouts.filter { $0.paceSeconds <= 1800 && $0.distanceKm >= 1.0 && $0.durationSeconds >= 120 }
        guard !valid.isEmpty else { return "No runs on record." }

        var parts: [String] = []

        let totalRuns = valid.count
        let totalDistance = valid.map(\.distanceKm).reduce(0, +)
        let avgDistance = totalDistance / Double(totalRuns)
        let avgPaceSec = weightedAvgPace(valid)
        let avgPaceStr = formatPace(avgPaceSec)
        parts.append("Your running history shows \(totalRuns) runs with a total distance of \(formatDistance(totalDistance)). Your average distance is \(formatDistance(avgDistance)) and your average pace is \(avgPaceStr).")

        if let longest = longestRun(from: valid) {
            parts.append("Your longest run was \(formatDistance(longest.distanceKm)) on \(formatDate(longest.startedAt)).")
        }
        if let fastest = fastestRun(from: valid) {
            parts.append("Your fastest pace was \(formatPace(fastest.paceSeconds)) on \(formatDate(fastest.startedAt)).")
        }
        if let slowest = slowestRun(from: valid) {
            parts.append("Your slowest pace was \(formatPace(slowest.paceSeconds)) on \(formatDate(slowest.startedAt)).")
        }

        let hrValues = valid.compactMap(\.heartRateAvgBpm)
        if !hrValues.isEmpty {
            parts.append("Your average heart rate across all runs is \(hrValues.reduce(0, +) / hrValues.count) bpm.")
        }

        let currStreak = computeCurrentStreak(from: valid)
        let longestStreak = computeLongestStreak(from: valid)
        parts.append("Your current running streak is \(currStreak) day\(currStreak == 1 ? "" : "s"). Your longest streak ever is \(longestStreak) day\(longestStreak == 1 ? "" : "s").")

        if let highest = mostElevation(from: valid), let elev = highest.elevationGainMetres, elev > 0 {
            parts.append("Your highest elevation gain was \(String(format: "%.0f", elev)) m on \(formatDate(highest.startedAt)).")
        }
        if let mostCals = mostCalories(from: valid), let cals = mostCals.activeCaloriesKcal, cals > 0 {
            parts.append("The most calories you burned in a single run was \(cals) kcal on \(formatDate(mostCals.startedAt)).")
        }

        return parts.joined(separator: " ")
    }

    // MARK: - Section Formatters

    private func formatGeneralSummary(_ workouts: [RunWorkout]) async -> String {
        let header: String
        if workouts.count <= 10 {
            header = "All runs in your history:\n"
        } else {
            header = "Your most recent runs (showing the latest 10 out of \(workouts.count) total):\n"
        }
        let recent = workouts.prefix(10).map(formatWorkoutLine).joined(separator: "\n")
        let trends = formatTrends(workouts)
        let recovery = await formatRecovery(workouts[0].startedAt)
        return header + recent + "\n\n" + trends + "\n\n" + recovery
    }

    private func formatTrends(_ workouts: [RunWorkout]) -> String {
        let weeks: Int
        if let first = workouts.first, let last = workouts.last {
            weeks = max(1, Calendar.current.dateComponents([.weekOfYear], from: last.startedAt, to: first.startedAt).weekOfYear ?? 1)
        } else {
            weeks = 1
        }
        let runsPerWeek = String(format: "%.1f", Double(workouts.count) / Double(weeks))

        var parts = ["Your training frequency is \(workouts.count) runs over \(weeks) weeks, which is \(runsPerWeek) runs per week."]

        let buckets = bucketizeByMonth(workouts).suffix(6)
        if buckets.count > 1 {
            var volParts = ["Monthly volume:"]
            for (label, runs) in buckets {
                volParts.append("\(label) had \(String(format: "%.1f", runs.map(\.distanceKm).reduce(0, +))) km across \(runs.count) runs")
            }
            parts.append(volParts.joined(separator: " "))
        }

        return parts.joined(separator: "\n")
    }

    private func formatRecovery(_ runDate: Date) async -> String {
        let bundles = await HealthKitRecoveryFetcher().fetchRecovery(for: [runDate])
        guard let bundle = bundles.first else {
            return "No recovery data is available for your last run."
        }

        var lines = ["Recovery metrics around your last run on \(formatDate(bundle.runStartedAt)):"]
        lines.append("Night before: \(formatRecoveryWindow(bundle.nightBefore))")
        lines.append("Day of the run: \(formatRecoveryWindow(bundle.runDay))")
        lines.append("Day after: \(formatRecoveryWindow(bundle.dayAfter))")

        return lines.joined(separator: "\n")
    }

    // MARK: - Line Formatters

    private func formatWorkoutLine(_ w: RunWorkout) -> String {
        var parts = [formatDate(w.startedAt) + ":"]
        parts.append("distance " + formatDistance(w.distanceKm))
        parts.append("pace " + formatPace(w.paceSeconds))
        parts.append("duration " + formatDuration(w.durationSeconds))
        if let hr = w.heartRateAvgBpm { parts.append("heart rate " + String(hr) + " bpm") }
        if let cal = w.activeCaloriesKcal { parts.append(String(cal) + " kcal") }
        if let elev = w.elevationGainMetres, elev > 0 {
            parts.append("elevation " + String(format: "%.0f", elev) + " m")
        }
        if let cadence = w.cadenceStepsPerMin { parts.append("cadence " + String(cadence) + " spm") }
        return parts.joined(separator: ", ")
    }

    private func formatPace(_ totalSeconds: Int) -> String {
        let capped = min(totalSeconds, 1800)
        let minutes = capped / 60
        let seconds = capped % 60
        return String(format: "%d min %02d sec per km", minutes, seconds)
    }

    private func formatDuration(_ totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 { return "\(hours) hr \(minutes) min" }
        if minutes > 0 { return "\(minutes) min \(secs) sec" }
        return "\(secs) sec"
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "d MMMM yyyy"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

    private func formatDistance(_ km: Double) -> String {
        String(format: "%.1f km", km)
    }

    private func formatRecoveryWindow(_ m: RecoveryMetrics) -> String {
        var parts: [String] = []
        if let sleep = m.sleepDurationHours { parts.append(String(format: "%.1f hours of sleep", sleep)) }
        if let hrv = m.hrvMs { parts.append(String(format: "%.0f ms HRV", hrv)) }
        if let rhr = m.restingHeartRateBpm { parts.append("\(rhr) bpm resting heart rate") }
        if let hrr = m.heartRateRecoveryBpm { parts.append("\(hrr) bpm heart rate recovery") }
        if let spo2 = m.oxygenSaturationPct { parts.append(String(format: "%.1f percent blood oxygen", spo2)) }
        if parts.isEmpty { return "No data" }
        return parts.joined(separator: ", ")
    }

    // MARK: - Pre-computation Helpers

    private func longestRun(from workouts: [RunWorkout]) -> RunWorkout? {
        workouts.max(by: { $0.distanceKm < $1.distanceKm })
    }

    private func fastestRun(from workouts: [RunWorkout]) -> RunWorkout? {
        workouts.min(by: { $0.paceSeconds < $1.paceSeconds })
    }

    private func slowestRun(from workouts: [RunWorkout]) -> RunWorkout? {
        workouts.max(by: { $0.paceSeconds < $1.paceSeconds })
    }

    private func mostElevation(from workouts: [RunWorkout]) -> RunWorkout? {
        workouts.max(by: { ($0.elevationGainMetres ?? 0) < ($1.elevationGainMetres ?? 0) })
    }

    private func mostCalories(from workouts: [RunWorkout]) -> RunWorkout? {
        workouts.max(by: { ($0.activeCaloriesKcal ?? 0) < ($1.activeCaloriesKcal ?? 0) })
    }

    private func weightedAvgPace(_ runs: [RunWorkout]) -> Int {
        let totalDuration = runs.map(\.durationSeconds).reduce(0, +)
        let totalDistance = runs.map(\.distanceKm).reduce(0, +)
        guard totalDistance > 0 else { return 0 }
        return Int(Double(totalDuration) / totalDistance)
    }

    private func computeCurrentStreak(from workouts: [RunWorkout]) -> Int {
        let cal = Calendar.current
        let runDays = Set(workouts.map { cal.startOfDay(for: $0.startedAt) }).sorted(by: >)
        guard let latest = runDays.first else { return 0 }

        var streak = 0
        var expected = latest
        for day in runDays {
            let diff = cal.dateComponents([.day], from: day, to: expected).day ?? 999
            if diff <= 1 { streak += 1; expected = day } else { break }
        }
        return streak
    }

    private func computeLongestStreak(from workouts: [RunWorkout]) -> Int {
        let cal = Calendar.current
        let runDays = Set(workouts.map { cal.startOfDay(for: $0.startedAt) }).sorted(by: >)
        guard runDays.count > 1 else { return runDays.count }

        var longest = 1
        var temp = 1
        for i in 1..<runDays.count {
            let diff = cal.dateComponents([.day], from: runDays[i], to: runDays[i - 1]).day ?? 0
            if diff == 1 {
                temp += 1
                longest = max(longest, temp)
            } else {
                temp = 1
            }
        }
        return longest
    }

    private func bucketizeByMonth(_ workouts: [RunWorkout]) -> [(String, [RunWorkout])] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        var dict: [String: [RunWorkout]] = [:]
        var order: [String] = []
        for w in workouts.sorted(by: { $0.startedAt < $1.startedAt }) {
            let key = formatter.string(from: w.startedAt)
            if dict[key] == nil { order.append(key) }
            dict[key, default: []].append(w)
        }
        return order.map { ($0, dict[$0]!) }
    }

}
