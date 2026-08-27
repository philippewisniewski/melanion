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

    func classify(_ question: String) -> Intent {
        let q = question.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

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

        if let n = extractNumber(after: "top", in: q) {
            if q.contains("longest") || q.contains("furthest") { return .topFew(n, attribute: .distance) }
            if q.contains("fastest") || q.contains("quickest") { return .topFew(n, attribute: .pace) }
            return .lastFew(n)
        }
        if let n = extractNumber(after: "last", in: q) { return .lastFew(n) }
        if let n = extractNumber(after: "recent", in: q) { return .lastFew(n) }

        if q.contains("average pace") || q.contains("avg pace") || q.contains("typical pace") || q.contains("pacing") { return .averagePace }
        if q.contains("average distance") || q.contains("avg distance") || q.contains("typical distance") { return .averageDistance }

        if q.contains("longest") || q.contains("furthest") || q.contains("max distance") { return .longestRun }
        if q.contains("fastest") || q.contains("best pace") || q.contains("quickest") { return .fastestRun }
        if q.contains("slowest") || q.contains("easiest") || q.contains("worst pace") { return .slowestRun }

        if q.contains("last run") || q.contains("latest run") || q.contains("most recent") {
            return .lastRun
        }
        if q.contains("split") { return .lastRun }

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

    // MARK: - Intent

    enum SortAttribute {
        case distance
        case pace
    }

    enum Intent {
        case lastRun
        case lastFew(Int)
        case topFew(Int, attribute: SortAttribute)
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

    // MARK: - Data Formatting

    private func formatData(for intent: Intent, workouts: [RunWorkout]) async -> String {
        guard !workouts.isEmpty else { return "No runs found." }

        switch intent {
        case .lastRun:
            return "Run data:\n" + formatStructured(workouts[0])

        case .lastFew(let n):
            let count = min(n, workouts.count)
            let lines = workouts.prefix(count).map(formatStructured)
            return "Run data (last \(count)):\n" + lines.joined(separator: "\n---\n")

        case .topFew(let n, let attribute):
            let sorted: [RunWorkout]
            let label: String
            switch attribute {
            case .distance:
                sorted = workouts.sorted { $0.distanceKm > $1.distanceKm }
                label = "distance"
            case .pace:
                sorted = workouts.sorted { $0.paceSeconds < $1.paceSeconds }
                label = "pace"
            }
            let count = min(n, sorted.count)
            let lines = sorted.prefix(count).map(formatStructured)
            return "Run data (top \(count) by \(label)):\n" + lines.joined(separator: "\n---\n")

        case .longestRun, .fastestRun, .slowestRun, .averagePace, .averageDistance, .total:
            return ""

        case .calories:
            let withCals = workouts.filter { $0.activeCaloriesKcal != nil }.prefix(10)
            guard !withCals.isEmpty else { return "" }
            return "Runs with calories:\n" + withCals.map(formatStructured).joined(separator: "\n---\n")

        case .elevation:
            let withElev = workouts
                .filter { $0.elevationGainMetres != nil && $0.elevationGainMetres! > 0 }
                .sorted { ($0.elevationGainMetres ?? 0) > ($1.elevationGainMetres ?? 0) }
                .prefix(10)
            guard !withElev.isEmpty else { return "" }
            return "Runs with elevation data:\n" + withElev.map(formatStructured).joined(separator: "\n---\n")

        case .streaks:
            let dates = workouts.prefix(20).map { formatDate($0.startedAt) }
            return "Recent run dates: " + dates.joined(separator: ", ")

        case .heartRate:
            let withHR = workouts.filter { $0.heartRateAvgBpm != nil }.prefix(10)
            guard !withHR.isEmpty else { return "" }
            return "Runs with heart rate:\n" + withHR.map(formatStructured).joined(separator: "\n---\n")

        case .cadence:
            let withCadence = workouts.filter { $0.cadenceStepsPerMin != nil }.prefix(10)
            guard !withCadence.isEmpty else { return "" }
            return "Runs with cadence:\n" + withCadence.map(formatStructured).joined(separator: "\n---\n")

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
        parts.append("Pre-computed stats: total_runs=\(totalRuns), total_distance_km=\(String(format: "%.2f", totalDistance)), avg_distance_km=\(String(format: "%.2f", avgDistance)), avg_pace_seconds=\(avgPaceSec)")

        let totalCalories = valid.compactMap(\.activeCaloriesKcal).reduce(0, +)
        parts.append("total_calories_kcal=\(totalCalories)")

        let totalElevation = valid.compactMap(\.elevationGainMetres).reduce(0, +)
        parts.append("total_elevation_metres=\(String(format: "%.0f", totalElevation))")

        let totalDuration = valid.map(\.durationSeconds).reduce(0, +)
        parts.append("total_duration_seconds=\(totalDuration)")

        if let longest = longestRun(from: valid) {
            parts.append("longest_run_distance_km=\(String(format: "%.2f", longest.distanceKm)), longest_run_date=\(formatDate(longest.startedAt))")
        }
        if let fastest = fastestRun(from: valid) {
            parts.append("fastest_pace_seconds=\(fastest.paceSeconds), fastest_pace_date=\(formatDate(fastest.startedAt))")
        }
        if let slowest = slowestRun(from: valid) {
            parts.append("slowest_pace_seconds=\(slowest.paceSeconds), slowest_pace_date=\(formatDate(slowest.startedAt))")
        }

        let hrValues = valid.compactMap(\.heartRateAvgBpm)
        if !hrValues.isEmpty {
            parts.append("avg_heart_rate_bpm=\(hrValues.reduce(0, +) / hrValues.count)")
        }

        let currStreak = computeCurrentStreak(from: valid)
        let longestStreak = computeLongestStreak(from: valid)
        parts.append("current_streak_days=\(currStreak), longest_streak_days=\(longestStreak)")

        if let highest = mostElevation(from: valid), let elev = highest.elevationGainMetres, elev > 0 {
            parts.append("highest_elevation_metres=\(String(format: "%.0f", elev)), highest_elevation_date=\(formatDate(highest.startedAt))")
        }
        if let mostCals = mostCalories(from: valid), let cals = mostCals.activeCaloriesKcal, cals > 0 {
            parts.append("most_calories_kcal=\(cals), most_calories_date=\(formatDate(mostCals.startedAt))")
        }

        return parts.joined(separator: "\n")
    }

    // MARK: - Section Formatters

    private func formatGeneralSummary(_ workouts: [RunWorkout]) async -> String {
        let header: String
        if workouts.count <= 10 {
            header = "All runs:\n"
        } else {
            header = "Most recent runs (latest 10 out of \(workouts.count)):\n"
        }
        let recent = workouts.prefix(10).map(formatStructured).joined(separator: "\n---\n")
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

        var parts = ["Training frequency: \(workouts.count) runs over \(weeks) weeks, \(runsPerWeek) runs per week."]

        let buckets = bucketizeByMonth(workouts).suffix(6)
        if buckets.count > 1 {
            var volParts = ["Monthly volumes:"]
            for (label, runs) in buckets {
                volParts.append("- \(label): \(String(format: "%.1f", runs.map(\.distanceKm).reduce(0, +))) km, \(runs.count) runs")
            }
            parts.append(volParts.joined(separator: "\n"))
        }

        return parts.joined(separator: "\n")
    }

    private func formatRecovery(_ runDate: Date) async -> String {
        let bundles = await HealthKitRecoveryFetcher().fetchRecovery(for: [runDate])
        guard let bundle = bundles.first else {
            return "Recovery data: not available for your last run."
        }

        var lines = ["Recovery metrics around \(formatDate(bundle.runStartedAt)):"]
        lines.append("Night before: " + formatRecoveryWindow(bundle.nightBefore))
        lines.append("Day of run: " + formatRecoveryWindow(bundle.runDay))
        lines.append("Day after: " + formatRecoveryWindow(bundle.dayAfter))

        return lines.joined(separator: "\n")
    }

    // MARK: - Line Formatters

    private func formatStructured(_ w: RunWorkout) -> String {
        var parts = ["date: \(formatDate(w.startedAt))"]
        parts.append("distance_km: \(String(format: "%.2f", w.distanceKm))")
        parts.append("pace_seconds: \(w.paceSeconds)")
        parts.append("duration_seconds: \(w.durationSeconds)")
        parts.append("start_hour: \(Calendar.current.component(.hour, from: w.startedAt))")
        if let hr = w.heartRateAvgBpm { parts.append("heart_rate_bpm: \(hr)") }
        if let cal = w.activeCaloriesKcal { parts.append("calories_kcal: \(cal)") }
        if let elev = w.elevationGainMetres, elev > 0 {
            parts.append("elevation_metres: \(String(format: "%.0f", elev))")
        }
        if let cadence = w.cadenceStepsPerMin { parts.append("cadence_spm: \(cadence)") }
        if let splits = w.splitsSecondsPerKm, !splits.isEmpty {
            parts.append("splits_per_km: " + splits.map { formatSplit($0) }.joined(separator: ", "))
        }
        return parts.joined(separator: "\n")
    }

    private func formatRecoveryWindow(_ m: RecoveryMetrics) -> String {
        var parts: [String] = []
        if let sleep = m.sleepDurationHours { parts.append("sleep_hours: \(String(format: "%.1f", sleep))") }
        if let hrv = m.hrvMs { parts.append("hrv_ms: \(String(format: "%.0f", hrv))") }
        if let rhr = m.restingHeartRateBpm { parts.append("resting_hr_bpm: \(rhr)") }
        if let hrr = m.heartRateRecoveryBpm { parts.append("hr_recovery_bpm: \(hrr)") }
        if let spo2 = m.oxygenSaturationPct { parts.append("blood_oxygen_pct: \(String(format: "%.1f", spo2))") }
        if parts.isEmpty { return "no_data" }
        return parts.joined(separator: ", ")
    }

    // MARK: - Pre-computation Helpers

    private func formatSplit(_ totalSeconds: Int) -> String {
        let capped = min(totalSeconds, 1800)
        return String(format: "%d:%02d", capped / 60, capped % 60)
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "d MMMM yyyy"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

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
