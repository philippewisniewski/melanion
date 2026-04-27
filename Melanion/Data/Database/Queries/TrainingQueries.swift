import Foundation
import GRDB

struct TrainingVolumeQuery: QueryDefinition {
    let name = "training_volume"
    let description = "Return total kilometres run per calendar week for the last N weeks."
    let format: ResponseFormat = .trend

    func execute(db: Database, params: [String: String]) throws -> [QueryRow] {
        let weeks = Int(params["weeks"] ?? "12") ?? 12
        let sql = """
            SELECT strftime('%Y-W%W', started_at) as week,
                   ROUND(SUM(distance_km),1) as total_km,
                   COUNT(*) as run_count
            FROM runs
            GROUP BY week
            ORDER BY week DESC
            LIMIT ?
            """
        return try Row.fetchAll(db, sql: sql, arguments: [weeks]).map { row in
            ["week": row["week"], "total_km": row["total_km"], "run_count": row["run_count"]]
        }
    }
}

struct RunFrequencyQuery: QueryDefinition {
    let name = "run_frequency"
    let description = "Return the average number of runs per week over the last N weeks."
    let format: ResponseFormat = .stat

    func execute(db: Database, params: [String: String]) throws -> [QueryRow] {
        let weeks = Int(params["weeks"] ?? "12") ?? 12
        let sql = """
            SELECT ROUND(CAST(COUNT(*) AS REAL) / ?, 1) as runs_per_week
            FROM runs
            WHERE started_at >= datetime('now', '-' || ? || ' weeks')
            """
        return try Row.fetchAll(db, sql: sql, arguments: [weeks, weeks]).map { row in
            ["runs_per_week": row["runs_per_week"]]
        }
    }
}

struct MonthlyRunsQuery: QueryDefinition {
    let name = "monthly_runs"
    let description = "Return run count, total distance, and average pace grouped by calendar month."
    let format: ResponseFormat = .trend

    func execute(db: Database, params: [String: String]) throws -> [QueryRow] {
        let sql = """
            SELECT year, month,
                   COUNT(*) as run_count,
                   ROUND(SUM(distance_km),1) as total_km,
                   ROUND(AVG(pace_seconds)) as avg_pace_seconds
            FROM runs
            GROUP BY year, month
            ORDER BY year DESC, month DESC
            LIMIT 24
            """
        return try Row.fetchAll(db, sql: sql, arguments: []).map { row in
            ["year": row["year"], "month": row["month"],
             "run_count": row["run_count"], "total_km": row["total_km"],
             "avg_pace_seconds": row["avg_pace_seconds"]]
        }
    }
}

struct RunningStreakQuery: QueryDefinition {
    let name = "running_streak"
    let description = "Return the current consecutive day running streak and the longest streak ever recorded."
    let format: ResponseFormat = .stat

    func execute(db: Database, params: [String: String]) throws -> [QueryRow] {
        let sql = "SELECT DISTINCT date FROM runs ORDER BY date DESC"
        let rows = try Row.fetchAll(db, sql: sql, arguments: [])
        let dateStrings: [String] = rows.compactMap { $0["date"] }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        let calendar = Calendar(identifier: .gregorian)
        let dates: [Date] = dateStrings.compactMap { formatter.date(from: $0) }
            .sorted(by: >)

        // Current streak: count consecutive days from today backwards
        var currentStreak = 0
        var today = calendar.startOfDay(for: Date())
        for date in dates {
            let d = calendar.startOfDay(for: date)
            if d == today || d == calendar.date(byAdding: .day, value: -1, to: today)! {
                currentStreak += 1
                today = d
            } else {
                break
            }
        }

        // Longest streak: sliding window
        var longestStreak = 0
        var currentWindow = 0
        let ascending = dates.sorted(by: <)
        for (i, date) in ascending.enumerated() {
            if i == 0 {
                currentWindow = 1
            } else {
                let prev = calendar.startOfDay(for: ascending[i - 1])
                let curr = calendar.startOfDay(for: date)
                let diff = calendar.dateComponents([.day], from: prev, to: curr).day ?? 0
                if diff == 1 {
                    currentWindow += 1
                } else {
                    currentWindow = 1
                }
            }
            longestStreak = max(longestStreak, currentWindow)
        }

        return [["current_streak": currentStreak, "longest_streak": longestStreak]]
    }
}

struct CalorieStatsQuery: QueryDefinition {
    let name = "calorie_stats"
    let description = "Return total and average active calories burned across all runs."
    let format: ResponseFormat = .stat

    func execute(db: Database, params: [String: String]) throws -> [QueryRow] {
        let sql = """
            SELECT SUM(active_calories_kcal) as total_calories_kcal,
                   ROUND(AVG(active_calories_kcal)) as avg_calories_kcal
            FROM runs
            WHERE active_calories_kcal IS NOT NULL
            """
        return try Row.fetchAll(db, sql: sql, arguments: []).map { row in
            ["total_calories_kcal": row["total_calories_kcal"],
             "avg_calories_kcal": row["avg_calories_kcal"]]
        }
    }
}
