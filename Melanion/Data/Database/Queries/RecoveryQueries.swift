import Foundation
import GRDB

struct RecoveryAnalysisQuery: QueryDefinition {
    let name = "recovery_analysis"
    let description = "Return HRV, resting heart rate, and sleep duration for runs in a date range."
    let format: ResponseFormat = .detail

    func execute(db: Database, params: [String: String]) throws -> [QueryRow] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        let today = formatter.string(from: Date())
        let thirtyDaysAgo: String = {
            let d = Calendar(identifier: .gregorian).date(byAdding: .day, value: -30, to: Date()) ?? Date()
            return formatter.string(from: d)
        }()

        let fromDate = params["fromDate"] ?? thirtyDaysAgo
        let toDate = params["toDate"] ?? today

        let sql = """
            SELECT r.date, rec.period, rec.hrv_ms, rec.resting_heart_rate_bpm, rec.sleep_duration_hours
            FROM runs r
            JOIN recovery rec ON rec.run_id = r.id
            WHERE r.date BETWEEN ? AND ?
            ORDER BY r.date ASC, rec.period
            """
        return try Row.fetchAll(db, sql: sql, arguments: [fromDate, toDate]).map { row in
            ["date": row["date"], "period": row["period"],
             "hrv_ms": row["hrv_ms"], "resting_heart_rate_bpm": row["resting_heart_rate_bpm"],
             "sleep_duration_hours": row["sleep_duration_hours"]]
        }
    }
}

struct RestingHRQuery: QueryDefinition {
    let name = "resting_hr"
    let description = "Return resting heart rate trend over time from run-day recovery data."
    let format: ResponseFormat = .trend

    func execute(db: Database, params: [String: String]) throws -> [QueryRow] {
        let sql = """
            SELECT r.date, rec.resting_heart_rate_bpm
            FROM runs r
            JOIN recovery rec ON rec.run_id = r.id
            WHERE rec.period = 'run_day' AND rec.resting_heart_rate_bpm IS NOT NULL
            ORDER BY r.date ASC
            """
        return try Row.fetchAll(db, sql: sql, arguments: []).map { row in
            ["date": row["date"], "resting_heart_rate_bpm": row["resting_heart_rate_bpm"]]
        }
    }
}

struct HRRangeQuery: QueryDefinition {
    let name = "hr_range"
    let description = "Return average minimum and maximum heart rate per run as a trend over time."
    let format: ResponseFormat = .trend

    func execute(db: Database, params: [String: String]) throws -> [QueryRow] {
        let sql = """
            SELECT date, heart_rate_min_bpm, heart_rate_avg_bpm, heart_rate_max_bpm
            FROM runs
            WHERE heart_rate_avg_bpm IS NOT NULL
            ORDER BY date ASC
            """
        return try Row.fetchAll(db, sql: sql, arguments: []).map { row in
            ["date": row["date"], "heart_rate_min_bpm": row["heart_rate_min_bpm"],
             "heart_rate_avg_bpm": row["heart_rate_avg_bpm"],
             "heart_rate_max_bpm": row["heart_rate_max_bpm"]]
        }
    }
}

struct HRRecoveryStatsQuery: QueryDefinition {
    let name = "hr_recovery_stats"
    let description = "Return one-minute heart rate recovery values over time."
    let format: ResponseFormat = .trend

    func execute(db: Database, params: [String: String]) throws -> [QueryRow] {
        let sql = """
            SELECT r.date, rec.heart_rate_recovery_bpm
            FROM runs r
            JOIN recovery rec ON rec.run_id = r.id
            WHERE rec.period = 'run_day' AND rec.heart_rate_recovery_bpm IS NOT NULL
            ORDER BY r.date ASC
            """
        return try Row.fetchAll(db, sql: sql, arguments: []).map { row in
            ["date": row["date"], "heart_rate_recovery_bpm": row["heart_rate_recovery_bpm"]]
        }
    }
}

struct SleepVsPaceQuery: QueryDefinition {
    let name = "sleep_vs_pace"
    let description = "Correlate night-before sleep duration with next-day run pace."
    let format: ResponseFormat = .trend

    func execute(db: Database, params: [String: String]) throws -> [QueryRow] {
        let sql = """
            SELECT r.date, rec.sleep_duration_hours, r.pace_seconds
            FROM runs r
            JOIN recovery rec ON rec.run_id = r.id
            WHERE rec.period = 'night_before' AND rec.sleep_duration_hours IS NOT NULL
            ORDER BY r.date ASC
            """
        return try Row.fetchAll(db, sql: sql, arguments: []).map { row in
            ["date": row["date"], "sleep_duration_hours": row["sleep_duration_hours"],
             "pace_seconds": row["pace_seconds"]]
        }
    }
}
