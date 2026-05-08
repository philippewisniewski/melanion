import Foundation

final class MilestoneDetector: @unchecked Sendable {
    static let shared = MilestoneDetector()
    private init() {}

    private static let notifiedKey = "melanion_notified_milestones"

    // MARK: - Entry point

    func evaluateAfterSync() async {
        do {
            let workouts = try await HealthKitWorkoutFetcher().fetchRunningWorkouts()
            guard let latest = workouts.first else { return }

            var notified = Self.loadNotified()
            var payloads: [NotificationPayload] = []

            if let p = Self.checkRunComplete(latest: latest, notified: &notified) { payloads.append(p) }
            if let p = Self.checkPacePB(latest: latest, workouts: workouts, notified: &notified) { payloads.append(p) }
            payloads += Self.checkDistanceBracketPBs(latest: latest, workouts: workouts, notified: &notified)
            if let p = Self.checkLongestRun(latest: latest, workouts: workouts, notified: &notified) { payloads.append(p) }
            payloads += Self.checkStreakMilestones(workouts: workouts, notified: &notified)
            if let p = Self.checkRunCountMilestone(count: workouts.count, notified: &notified) { payloads.append(p) }
            if let p = Self.checkWeeklyTrend(workouts: workouts, notified: &notified) { payloads.append(p) }

            if let p = await Self.checkRecoveryNudge(latest: latest, workouts: workouts, notified: &notified) {
                payloads.append(p)
            }

            Self.saveNotified(notified)

            guard !payloads.isEmpty else { return }
            let settings = NotificationSettings.load()
            for payload in payloads where Self.isEnabled(payload.category, in: settings) {
                NotificationService.shared.schedule(payload)
            }
        } catch { }
    }

    // MARK: - Dedup persistence (UserDefaults)

    private static func loadNotified() -> Set<String> {
        let array = UserDefaults.standard.stringArray(forKey: notifiedKey) ?? []
        return Set(array)
    }

    private static func saveNotified(_ keys: Set<String>) {
        UserDefaults.standard.set(Array(keys), forKey: notifiedKey)
    }

    private static func mark(key: String, notified: inout Set<String>) {
        notified.insert(key)
    }

    // MARK: - Run complete

    private static func checkRunComplete(
        latest: RunWorkout, notified: inout Set<String>
    ) -> NotificationPayload? {
        let key = "run_complete_\(isoString(latest.startedAt))"
        guard !notified.contains(key) else { return nil }

        let cutoff = Date().addingTimeInterval(-86_400)
        guard latest.startedAt > cutoff else { return nil }

        mark(key: key, notified: &notified)
        let dist = String(format: "%.1f km", latest.distanceKm)
        let pace = formatPace(latest.paceSeconds)
        return NotificationPayload(
            id: key,
            title: "Run logged",
            body: "\(dist) at \(pace)/km. Open Melanion for your coaching summary.",
            category: .runComplete
        )
    }

    // MARK: - All-time pace PB

    private static func checkPacePB(
        latest: RunWorkout, workouts: [RunWorkout], notified: inout Set<String>
    ) -> NotificationPayload? {
        let key = "pb_pace_alltime_\(isoString(latest.startedAt))"
        guard !notified.contains(key) else { return nil }
        guard workouts.count > 1 else { return nil }

        let fastest = workouts.min(by: { $0.paceSeconds < $1.paceSeconds })
        guard fastest?.startedAt == latest.startedAt else { return nil }

        let prevBest = workouts.filter { $0.startedAt != latest.startedAt }
            .min(by: { $0.paceSeconds < $1.paceSeconds })
        let diff = (prevBest?.paceSeconds ?? latest.paceSeconds) - latest.paceSeconds
        let improvStr = diff > 0 ? " — \(formatPace(diff)) faster than your previous best." : "."

        mark(key: key, notified: &notified)
        return NotificationPayload(
            id: key,
            title: "New all-time pace PB",
            body: "Best ever: \(formatPace(latest.paceSeconds))/km\(improvStr)",
            category: .personalBest
        )
    }

    // MARK: - Distance bracket PBs

    private static let distanceBrackets: [(label: String, min: Double, max: Double)] = [
        ("5 km",           4.0,  7.0),
        ("10 km",          8.0, 13.0),
        ("half-marathon", 19.0, 23.0),
        ("marathon",      40.0, 45.0),
    ]

    private static func checkDistanceBracketPBs(
        latest: RunWorkout, workouts: [RunWorkout], notified: inout Set<String>
    ) -> [NotificationPayload] {
        var payloads: [NotificationPayload] = []
        for bracket in distanceBrackets {
            guard latest.distanceKm >= bracket.min && latest.distanceKm < bracket.max else { continue }
            let key = "pb_pace_\(bracket.label.replacingOccurrences(of: " ", with: "_"))_\(isoString(latest.startedAt))"
            guard !notified.contains(key) else { continue }

            let inBracket = workouts.filter { $0.distanceKm >= bracket.min && $0.distanceKm < bracket.max }
            guard inBracket.count > 1 else { continue }

            let fastest = inBracket.min(by: { $0.paceSeconds < $1.paceSeconds })
            guard fastest?.startedAt == latest.startedAt else { continue }

            mark(key: key, notified: &notified)
            payloads.append(NotificationPayload(
                id: key,
                title: "New \(bracket.label) PB",
                body: "\(formatPace(latest.paceSeconds))/km — your fastest \(bracket.label) yet.",
                category: .personalBest
            ))
        }
        return payloads
    }

    // MARK: - Longest run PB

    private static func checkLongestRun(
        latest: RunWorkout, workouts: [RunWorkout], notified: inout Set<String>
    ) -> NotificationPayload? {
        let key = "pb_distance_alltime_\(isoString(latest.startedAt))"
        guard !notified.contains(key) else { return nil }
        guard workouts.count > 1 else { return nil }

        let farthest = workouts.max(by: { $0.distanceKm < $1.distanceKm })
        guard farthest?.startedAt == latest.startedAt else { return nil }

        mark(key: key, notified: &notified)
        let dist = String(format: "%.1f km", latest.distanceKm)
        return NotificationPayload(
            id: key,
            title: "Longest run ever",
            body: "\(dist) — a new distance PB. Coach has thoughts on your pacing.",
            category: .personalBest
        )
    }

    // MARK: - Streak milestones

    private static let streakThresholds = [7, 14, 30, 50, 100]

    private static func checkStreakMilestones(
        workouts: [RunWorkout], notified: inout Set<String>
    ) -> [NotificationPayload] {
        var payloads: [NotificationPayload] = []
        let cal = Calendar(identifier: .gregorian)
        let dates = Set(workouts.map { cal.startOfDay(for: $0.startedAt) }).sorted(by: >)
        guard !dates.isEmpty else { return payloads }

        var currentStreak = 0
        var cursor = cal.startOfDay(for: Date())
        for date in dates {
            let d = cal.startOfDay(for: date)
            if d == cursor || d == cal.date(byAdding: .day, value: -1, to: cursor)! {
                currentStreak += 1
                cursor = d
            } else {
                break
            }
        }

        for threshold in streakThresholds where currentStreak == threshold {
            let key = "streak_\(threshold)"
            guard !notified.contains(key) else { continue }
            mark(key: key, notified: &notified)
            payloads.append(NotificationPayload(
                id: key,
                title: "Streak milestone",
                body: streakMessage(threshold),
                category: .streakMilestone
            ))
        }

        if dates.count >= 2 {
            let latest = dates[0]
            let previous = dates[1]
            let gap = cal.dateComponents([.day], from: previous, to: latest).day ?? 0
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let key = "return_from_gap_\(formatter.string(from: latest))"
            if gap > 14 && !notified.contains(key) {
                mark(key: key, notified: &notified)
                payloads.append(NotificationPayload(
                    id: key,
                    title: "Welcome back",
                    body: "First run in \(gap) days. Good to have you back.",
                    category: .streakMilestone
                ))
            }
        }

        return payloads
    }

    // MARK: - Run count milestones

    private static let countThresholds = [10, 25, 50, 100, 250]

    private static func checkRunCountMilestone(
        count: Int, notified: inout Set<String>
    ) -> NotificationPayload? {
        for threshold in countThresholds where count == threshold {
            let key = "run_count_\(threshold)"
            guard !notified.contains(key) else { return nil }
            mark(key: key, notified: &notified)
            return NotificationPayload(
                id: key,
                title: "Milestone",
                body: runCountMessage(threshold),
                category: .streakMilestone
            )
        }
        return nil
    }

    // MARK: - Weekly pace trend

    private static func checkWeeklyTrend(
        workouts: [RunWorkout], notified: inout Set<String>
    ) -> NotificationPayload? {
        let cal = Calendar(identifier: .gregorian)
        let weekOfYear = cal.component(.weekOfYear, from: Date())
        let year = cal.component(.year, from: Date())
        let key = "weekly_trend_\(year)_W\(weekOfYear)"
        guard !notified.contains(key) else { return nil }

        let now = Date()
        let fourWeeksAgo = cal.date(byAdding: .weekOfYear, value: -4, to: now)!
        let eightWeeksAgo = cal.date(byAdding: .weekOfYear, value: -8, to: now)!

        let recent = workouts.filter { $0.startedAt >= fourWeeksAgo }
        let prior = workouts.filter { $0.startedAt >= eightWeeksAgo && $0.startedAt < fourWeeksAgo }

        guard !recent.isEmpty, !prior.isEmpty else { return nil }
        let recentAvg = Double(recent.map(\.paceSeconds).reduce(0, +)) / Double(recent.count)
        let priorAvg = Double(prior.map(\.paceSeconds).reduce(0, +)) / Double(prior.count)
        guard priorAvg > 0, recentAvg > 0 else { return nil }

        let improvePct = (priorAvg - recentAvg) / priorAvg * 100
        guard improvePct >= 3 else { return nil }

        mark(key: key, notified: &notified)

        var components = DateComponents()
        components.weekday = 2
        components.hour = 8
        components.minute = 0
        return NotificationPayload(
            id: key,
            title: "Weekly update",
            body: String(format: "Your average pace improved %.1f%% this month. Momentum is building.", improvePct),
            category: .weeklyTrend,
            components: components
        )
    }

    // MARK: - Recovery nudge

    private static func checkRecoveryNudge(
        latest: RunWorkout, workouts: [RunWorkout], notified: inout Set<String>
    ) async -> NotificationPayload? {
        let key = "recovery_nudge_\(isoString(latest.startedAt))"
        guard !notified.contains(key) else { return nil }

        let profile = UserProfile.load()
        let maxHR = profile.maxHeartRate ?? 190
        let hrHard = (latest.heartRateAvgBpm ?? 0) > Int(Double(maxHR) * 0.85)
        let distHard = latest.distanceKm > 15
        let elevHard = (latest.elevationGainMetres ?? 0) > 200
        guard hrHard || distHard || elevHard else { return nil }

        let bundles = await HealthKitRecoveryFetcher().fetchRecovery(for: [latest.startedAt])
        guard let bundle = bundles.first,
              let latestHrv = bundle.runDay.hrvMs else { return nil }

        let recentDates = workouts.prefix(30).map(\.startedAt).filter { $0 < latest.startedAt }
        guard !recentDates.isEmpty else { return nil }

        let recentBundles = await HealthKitRecoveryFetcher().fetchRecovery(for: Array(recentDates))
        let hrvValues = recentBundles.compactMap(\.runDay.hrvMs)
        guard !hrvValues.isEmpty else { return nil }

        let baselineHrv = hrvValues.reduce(0, +) / Double(hrvValues.count)
        guard baselineHrv > 0 else { return nil }

        let dropPct = (baselineHrv - latestHrv) / baselineHrv * 100
        guard dropPct >= 15 else { return nil }

        mark(key: key, notified: &notified)

        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        var components = Calendar.current.dateComponents([.year, .month, .day], from: tomorrow)
        components.hour = 7
        components.minute = 0
        return NotificationPayload(
            id: key,
            title: "Recovery check",
            body: "Your HRV dipped after yesterday's effort. Today might be better as a rest or easy day.",
            category: .recoveryNudge,
            components: components
        )
    }

    // MARK: - Helpers

    private static func isEnabled(_ category: NotificationPayload.Category, in s: NotificationSettings) -> Bool {
        switch category {
        case .runComplete:     return s.runComplete
        case .personalBest:   return s.personalBest
        case .weeklyTrend:    return s.weeklyTrend
        case .recoveryNudge:  return s.recoveryNudge
        case .streakMilestone: return s.streakMilestone
        }
    }

    private static func formatPace(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private static func isoString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func streakMessage(_ days: Int) -> String {
        switch days {
        case 7:   return "7-day streak. Habit forming."
        case 14:  return "Two weeks straight. That's real commitment."
        case 30:  return "30-day streak. Serious consistency."
        case 50:  return "50 days in a row. Impressive."
        case 100: return "100-day streak. That's elite consistency."
        default:  return "\(days)-day running streak."
        }
    }

    private static func runCountMessage(_ count: Int) -> String {
        switch count {
        case 10:  return "Run #10. You're getting started."
        case 25:  return "25 runs logged."
        case 50:  return "50 runs. Halfway to triple digits."
        case 100: return "Run #100. Welcome to the triple digits."
        case 250: return "250 runs. That's a serious running log."
        default:  return "Run #\(count) logged."
        }
    }
}
