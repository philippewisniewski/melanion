import Foundation
import GRDB

// Detects run milestones after each HealthKit sync and schedules local notifications.
// Uses the notified_milestones table to ensure each event fires at most once.
final class MilestoneDetector: @unchecked Sendable {
    static let shared = MilestoneDetector()
    private init() {}

    // MARK: - Entry point

    func evaluateAfterSync() async {
        let now = ISO8601DateFormatter().string(from: Date())
        do {
            let payloads = try await DatabaseManager.shared.db.write { db -> [NotificationPayload] in
                try Self.detect(in: db, now: now)
            }
            guard !payloads.isEmpty else { return }
            let settings = NotificationSettings.load()
            for payload in payloads where Self.isEnabled(payload.category, in: settings) {
                NotificationService.shared.schedule(payload)
            }
        } catch { }
    }

    // MARK: - Detection (synchronous, runs inside GRDB write closure)

    private static func detect(in db: Database, now: String) throws -> [NotificationPayload] {
        var payloads: [NotificationPayload] = []

        // Load all already-notified keys in one pass.
        let notified = Set<String>(
            try Row.fetchAll(db, sql: "SELECT key FROM notified_milestones").compactMap { $0["key"] as? String }
        )

        guard let latest = try RunRecord.order(Column("started_at").desc).fetchOne(db) else {
            return payloads
        }

        // Run complete (only for runs within the last 24 hours)
        if let p = try checkRunComplete(latest: latest, db: db, notified: notified, now: now) { payloads.append(p) }

        // All-time pace PB
        if let p = try checkPacePB(latest: latest, db: db, notified: notified, now: now) { payloads.append(p) }

        // Per-bracket distance PBs (5 k, 10 k, half, marathon)
        payloads += try checkDistanceBracketPBs(latest: latest, db: db, notified: notified, now: now)

        // Longest run PB (by distance)
        if let p = try checkLongestRun(latest: latest, db: db, notified: notified, now: now) { payloads.append(p) }

        // Streak milestones and welcome-back
        payloads += try checkStreakMilestones(db: db, notified: notified, now: now)

        // Run count milestones
        if let p = try checkRunCountMilestone(db: db, notified: notified, now: now) { payloads.append(p) }

        // Weekly pace trend (schedule for next Monday morning)
        if let p = try checkWeeklyTrend(db: db, notified: notified, now: now) { payloads.append(p) }

        // Recovery nudge (hard run + suppressed HRV)
        if let p = try checkRecoveryNudge(latest: latest, db: db, notified: notified, now: now) { payloads.append(p) }

        return payloads
    }

    // MARK: - Run complete

    private static func checkRunComplete(
        latest: RunRecord, db: Database, notified: Set<String>, now: String
    ) throws -> NotificationPayload? {
        let key = "run_complete_\(latest.startedAt)"
        guard !notified.contains(key) else { return nil }

        // Only notify for runs that started within the last 24 hours.
        let cutoff = Date().addingTimeInterval(-86_400)
        let cutoffStr = ISO8601DateFormatter().string(from: cutoff)
        guard latest.startedAt > cutoffStr else { return nil }

        try mark(key: key, now: now, in: db)
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
        latest: RunRecord, db: Database, notified: Set<String>, now: String
    ) throws -> NotificationPayload? {
        let key = "pb_pace_alltime_\(latest.startedAt)"
        guard !notified.contains(key) else { return nil }

        // Get the fastest run ever; if it's the latest, it's a new PB.
        guard let bestRow = try Row.fetchOne(db, sql: """
            SELECT started_at, pace_seconds FROM runs
            ORDER BY pace_seconds ASC, started_at DESC
            LIMIT 1
            """) else { return nil }

        let bestStartedAt: String = bestRow["started_at"] ?? ""
        guard bestStartedAt == latest.startedAt else { return nil }

        // Also confirm there was a prior run to beat (otherwise it's just the first run).
        let runCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM runs") ?? 0
        guard runCount > 1 else { return nil }

        // Find the previous best pace (second fastest).
        guard let prevRow = try Row.fetchOne(db, sql: """
            SELECT pace_seconds FROM runs
            WHERE started_at != ?
            ORDER BY pace_seconds ASC
            LIMIT 1
            """, arguments: [latest.startedAt]) else { return nil }

        let prevPace: Int = prevRow["pace_seconds"] ?? latest.paceSeconds
        let diff = prevPace - latest.paceSeconds
        let improvStr = diff > 0 ? " — \(formatPace(diff)) faster than your previous best." : "."

        try mark(key: key, now: now, in: db)
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
        latest: RunRecord, db: Database, notified: Set<String>, now: String
    ) throws -> [NotificationPayload] {
        var payloads: [NotificationPayload] = []
        for bracket in distanceBrackets {
            guard latest.distanceKm >= bracket.min && latest.distanceKm < bracket.max else { continue }
            let key = "pb_pace_\(bracket.label.replacingOccurrences(of: " ", with: "_"))_\(latest.startedAt)"
            guard !notified.contains(key) else { continue }

            guard let bestRow = try Row.fetchOne(db, sql: """
                SELECT started_at FROM runs
                WHERE distance_km >= ? AND distance_km < ?
                ORDER BY pace_seconds ASC, started_at DESC
                LIMIT 1
                """, arguments: [bracket.min, bracket.max]) else { continue }

            let bestStartedAt: String = bestRow["started_at"] ?? ""
            guard bestStartedAt == latest.startedAt else { continue }

            // Require at least one prior run in the bracket to beat.
            let bracketCount = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM runs WHERE distance_km >= ? AND distance_km < ?
                """, arguments: [bracket.min, bracket.max]) ?? 0
            guard bracketCount > 1 else { continue }

            try mark(key: key, now: now, in: db)
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
        latest: RunRecord, db: Database, notified: Set<String>, now: String
    ) throws -> NotificationPayload? {
        let key = "pb_distance_alltime_\(latest.startedAt)"
        guard !notified.contains(key) else { return nil }

        guard let farthestRow = try Row.fetchOne(db, sql: """
            SELECT started_at, distance_km FROM runs
            ORDER BY distance_km DESC, started_at DESC
            LIMIT 1
            """) else { return nil }

        let farthestStartedAt: String = farthestRow["started_at"] ?? ""
        guard farthestStartedAt == latest.startedAt else { return nil }

        let runCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM runs") ?? 0
        guard runCount > 1 else { return nil }

        try mark(key: key, now: now, in: db)
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
        db: Database, notified: Set<String>, now: String
    ) throws -> [NotificationPayload] {
        var payloads: [NotificationPayload] = []

        let rows = try Row.fetchAll(db, sql: "SELECT DISTINCT date FROM runs ORDER BY date DESC")
        let dateStrings: [String] = rows.compactMap { $0["date"] }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let calendar = Calendar(identifier: .gregorian)

        let dates: [Date] = dateStrings.compactMap { formatter.date(from: $0) }.sorted(by: >)

        // Current streak
        var currentStreak = 0
        var cursor = calendar.startOfDay(for: Date())
        for date in dates {
            let d = calendar.startOfDay(for: date)
            if d == cursor || d == calendar.date(byAdding: .day, value: -1, to: cursor)! {
                currentStreak += 1
                cursor = d
            } else {
                break
            }
        }

        for threshold in streakThresholds where currentStreak == threshold {
            let key = "streak_\(threshold)"
            guard !notified.contains(key) else { continue }
            try mark(key: key, now: now, in: db)
            payloads.append(NotificationPayload(
                id: key,
                title: "Streak milestone",
                body: streakMessage(threshold),
                category: .streakMilestone
            ))
        }

        // Welcome back: latest two distinct dates separated by > 14 days
        if dates.count >= 2 {
            let latest = dates[0]
            let previous = dates[1]
            let gap = calendar.dateComponents([.day], from: previous, to: latest).day ?? 0
            let latestStr = formatter.string(from: latest)
            let key = "return_from_gap_\(latestStr)"
            if gap > 14 && !notified.contains(key) {
                try mark(key: key, now: now, in: db)
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
        db: Database, notified: Set<String>, now: String
    ) throws -> NotificationPayload? {
        let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM runs") ?? 0
        for threshold in countThresholds where count == threshold {
            let key = "run_count_\(threshold)"
            guard !notified.contains(key) else { return nil }
            try mark(key: key, now: now, in: db)
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
        db: Database, notified: Set<String>, now: String
    ) throws -> NotificationPayload? {
        let calendar = Calendar(identifier: .gregorian)
        let weekOfYear = calendar.component(.weekOfYear, from: Date())
        let year = calendar.component(.year, from: Date())
        let key = "weekly_trend_\(year)_W\(weekOfYear)"
        guard !notified.contains(key) else { return nil }

        // Average pace: last 4 weeks vs. prior 4 weeks.
        let rows = try Row.fetchAll(db, sql: """
            SELECT
                ROUND(AVG(CASE WHEN started_at >= datetime('now', '-4 weeks') THEN pace_seconds END)) AS recent_avg,
                ROUND(AVG(CASE WHEN started_at < datetime('now', '-4 weeks')
                               AND started_at >= datetime('now', '-8 weeks') THEN pace_seconds END)) AS prior_avg
            FROM runs
            """)
        guard let row = rows.first,
              let recentAvg = row["recent_avg"] as? Double,
              let priorAvg = row["prior_avg"] as? Double,
              priorAvg > 0, recentAvg > 0 else { return nil }

        // Improvement means pace went DOWN (fewer seconds/km).
        let improvePct = (priorAvg - recentAvg) / priorAvg * 100
        guard improvePct >= 3 else { return nil }

        try mark(key: key, now: now, in: db)

        // Schedule for next Monday at 08:00.
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
        latest: RunRecord, db: Database, notified: Set<String>, now: String
    ) throws -> NotificationPayload? {
        let key = "recovery_nudge_\(latest.startedAt)"
        guard !notified.contains(key) else { return nil }

        // Determine if the latest run qualifies as "hard".
        let profile = UserProfile.load()
        let maxHR = profile.maxHeartRate ?? 190
        let hrHard = (latest.heartRateAvgBpm ?? 0) > Int(Double(maxHR) * 0.85)
        let distHard = latest.distanceKm > 15
        let elevHard = (latest.elevationGainMetres ?? 0) > 200
        guard hrHard || distHard || elevHard else { return nil }

        // Compare run-day HRV against the 30-day baseline.
        guard let latestRunId = latest.id else { return nil }
        guard let hrvRow = try Row.fetchOne(db, sql: """
            SELECT hrv_ms FROM recovery
            WHERE run_id = ? AND period = 'run_day' AND hrv_ms IS NOT NULL
            """, arguments: [latestRunId]),
              let latestHrv = hrvRow["hrv_ms"] as? Double else { return nil }

        guard let baselineRow = try Row.fetchOne(db, sql: """
            SELECT AVG(rec.hrv_ms) AS avg_hrv
            FROM recovery rec
            JOIN runs r ON r.id = rec.run_id
            WHERE rec.period = 'run_day'
              AND rec.hrv_ms IS NOT NULL
              AND r.started_at < ?
              AND r.started_at >= datetime(?, '-30 days')
            """, arguments: [latest.startedAt, latest.startedAt]),
              let baselineHrv = baselineRow["avg_hrv"] as? Double,
              baselineHrv > 0 else { return nil }

        let dropPct = (baselineHrv - latestHrv) / baselineHrv * 100
        guard dropPct >= 15 else { return nil }

        try mark(key: key, now: now, in: db)

        // Schedule for tomorrow at 07:00.
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

    private static func mark(key: String, now: String, in db: Database) throws {
        try db.execute(
            sql: "INSERT OR IGNORE INTO notified_milestones (key, fired_at) VALUES (?, ?)",
            arguments: [key, now]
        )
    }

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

