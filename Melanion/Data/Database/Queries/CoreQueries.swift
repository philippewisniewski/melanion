import Foundation
import GRDB

struct RecentRunsQuery: QueryDefinition {
    let name = "recent_runs"
    let description = "Return the N most recent runs with date, distance, pace, and average heart rate."
    let format: ResponseFormat = .detail

    func execute(db: Database, params: [String: String]) throws -> [QueryRow] {
        let n = Int(params["n"] ?? "10") ?? 10
        let sql = """
            SELECT date, distance_km, pace_seconds, heart_rate_avg_bpm, elevation_gain_metres
            FROM runs
            ORDER BY started_at DESC
            LIMIT ?
            """
        return try Row.fetchAll(db, sql: sql, arguments: [n]).map { row in
            ["date": row["date"], "distance_km": row["distance_km"],
             "pace_seconds": row["pace_seconds"], "heart_rate_avg_bpm": row["heart_rate_avg_bpm"],
             "elevation_gain_metres": row["elevation_gain_metres"]]
        }
    }
}

struct PersonalBestQuery: QueryDefinition {
    let name = "personal_best"
    let description = "Find the single fastest pace recorded for runs between a minimum and maximum distance in km."
    let format: ResponseFormat = .stat

    func execute(db: Database, params: [String: String]) throws -> [QueryRow] {
        let minKm = Double(params["minKm"] ?? "0") ?? 0.0
        let maxKm = Double(params["maxKm"] ?? "999") ?? 999.0
        let sql = """
            SELECT date, distance_km, pace_seconds, heart_rate_avg_bpm
            FROM runs
            WHERE distance_km >= ? AND distance_km <= ?
            ORDER BY pace_seconds ASC
            LIMIT 1
            """
        return try Row.fetchAll(db, sql: sql, arguments: [minKm, maxKm]).map { row in
            ["date": row["date"], "distance_km": row["distance_km"],
             "pace_seconds": row["pace_seconds"], "heart_rate_avg_bpm": row["heart_rate_avg_bpm"]]
        }
    }
}

struct DistanceBestQuery: QueryDefinition {
    let name = "distance_best"
    let description = "Find the longest single run by distance in km."
    let format: ResponseFormat = .stat

    func execute(db: Database, params: [String: String]) throws -> [QueryRow] {
        let sql = """
            SELECT date, distance_km, pace_seconds, duration_seconds
            FROM runs
            ORDER BY distance_km DESC
            LIMIT 1
            """
        return try Row.fetchAll(db, sql: sql, arguments: []).map { row in
            ["date": row["date"], "distance_km": row["distance_km"],
             "pace_seconds": row["pace_seconds"], "duration_seconds": row["duration_seconds"]]
        }
    }
}

struct DistanceTopNQuery: QueryDefinition {
    let name = "distance_top_n"
    let description = "Return the top N runs ranked by distance."
    let format: ResponseFormat = .rankedList

    func execute(db: Database, params: [String: String]) throws -> [QueryRow] {
        let n = Int(params["n"] ?? "5") ?? 5
        let sql = """
            SELECT date, distance_km, pace_seconds, duration_seconds
            FROM runs
            ORDER BY distance_km DESC
            LIMIT ?
            """
        return try Row.fetchAll(db, sql: sql, arguments: [n]).map { row in
            ["date": row["date"], "distance_km": row["distance_km"],
             "pace_seconds": row["pace_seconds"], "duration_seconds": row["duration_seconds"]]
        }
    }
}

struct OverallAveragesQuery: QueryDefinition {
    let name = "overall_averages"
    let description = "Return overall averages for pace, distance, heart rate, and elevation gain across all runs."
    let format: ResponseFormat = .stat

    func execute(db: Database, params: [String: String]) throws -> [QueryRow] {
        let sql = """
            SELECT ROUND(AVG(pace_seconds)) as pace_seconds,
                   ROUND(AVG(distance_km),2) as distance_km,
                   ROUND(AVG(heart_rate_avg_bpm)) as heart_rate_avg_bpm,
                   ROUND(AVG(elevation_gain_metres),1) as elevation_gain_metres
            FROM runs
            """
        return try Row.fetchAll(db, sql: sql, arguments: []).map { row in
            ["pace_seconds": row["pace_seconds"], "distance_km": row["distance_km"],
             "heart_rate_avg_bpm": row["heart_rate_avg_bpm"],
             "elevation_gain_metres": row["elevation_gain_metres"]]
        }
    }
}

struct PaceThresholdQuery: QueryDefinition {
    let name = "pace_threshold"
    let description = "Return all runs faster than a given pace in seconds per km."
    let format: ResponseFormat = .rankedList

    func execute(db: Database, params: [String: String]) throws -> [QueryRow] {
        let thresholdPace = Int(params["thresholdPace"] ?? "300") ?? 300
        let sql = """
            SELECT date, distance_km, pace_seconds, heart_rate_avg_bpm
            FROM runs
            WHERE pace_seconds < ?
            ORDER BY pace_seconds ASC
            """
        return try Row.fetchAll(db, sql: sql, arguments: [thresholdPace]).map { row in
            ["date": row["date"], "distance_km": row["distance_km"],
             "pace_seconds": row["pace_seconds"], "heart_rate_avg_bpm": row["heart_rate_avg_bpm"]]
        }
    }
}

struct HRThresholdQuery: QueryDefinition {
    let name = "hr_threshold"
    let description = "Return runs where average heart rate is above or below a given beats per minute value."
    let format: ResponseFormat = .rankedList

    func execute(db: Database, params: [String: String]) throws -> [QueryRow] {
        let bpm = Int(params["bpm"] ?? "160") ?? 160
        let direction = params["direction"] ?? "above"
        let op = direction == "above" ? ">" : "<"
        let sql = """
            SELECT date, distance_km, pace_seconds, heart_rate_avg_bpm
            FROM runs
            WHERE heart_rate_avg_bpm \(op) ?
            ORDER BY heart_rate_avg_bpm ASC
            """
        return try Row.fetchAll(db, sql: sql, arguments: [bpm]).map { row in
            ["date": row["date"], "distance_km": row["distance_km"],
             "pace_seconds": row["pace_seconds"], "heart_rate_avg_bpm": row["heart_rate_avg_bpm"]]
        }
    }
}

struct PacingPatternQuery: QueryDefinition {
    let name = "pacing_pattern"
    let description = "Show a breakdown of runs by pacing pattern: negative split, positive split, and even split counts."
    let format: ResponseFormat = .stat

    func execute(db: Database, params: [String: String]) throws -> [QueryRow] {
        let sql = """
            SELECT pacing_pattern, COUNT(*) as count
            FROM runs
            WHERE pacing_pattern IS NOT NULL
            GROUP BY pacing_pattern
            ORDER BY count DESC
            """
        return try Row.fetchAll(db, sql: sql, arguments: []).map { row in
            ["pacing_pattern": row["pacing_pattern"], "count": row["count"]]
        }
    }
}

struct KmSplitAnalysisQuery: QueryDefinition {
    let name = "km_split_analysis"
    let description = "Return per-kilometre split times and elevation for a specific run date."
    let format: ResponseFormat = .detail

    func execute(db: Database, params: [String: String]) throws -> [QueryRow] {
        let date: String
        if let d = params["date"] {
            date = d
        } else {
            let latestSQL = "SELECT date FROM runs ORDER BY started_at DESC LIMIT 1"
            if let row = try Row.fetchOne(db, sql: latestSQL, arguments: []) {
                date = row["date"] ?? ""
            } else {
                date = ""
            }
        }
        let sql = """
            SELECT rs.km, rs.split_seconds, rs.elevation_gain_m, rs.elevation_loss_m
            FROM route_splits rs
            JOIN runs r ON r.id = rs.run_id
            WHERE r.date = ?
            ORDER BY rs.km ASC
            """
        return try Row.fetchAll(db, sql: sql, arguments: [date]).map { row in
            ["km": row["km"], "split_seconds": row["split_seconds"],
             "elevation_gain_m": row["elevation_gain_m"], "elevation_loss_m": row["elevation_loss_m"]]
        }
    }
}

struct DurationStatsQuery: QueryDefinition {
    let name = "duration_stats"
    let description = "Return average, longest, and shortest run duration in seconds."
    let format: ResponseFormat = .stat

    func execute(db: Database, params: [String: String]) throws -> [QueryRow] {
        let sql = """
            SELECT ROUND(AVG(duration_seconds)) as avg_duration_seconds,
                   MAX(duration_seconds) as max_duration_seconds,
                   MIN(duration_seconds) as min_duration_seconds
            FROM runs
            """
        return try Row.fetchAll(db, sql: sql, arguments: []).map { row in
            ["avg_duration_seconds": row["avg_duration_seconds"],
             "max_duration_seconds": row["max_duration_seconds"],
             "min_duration_seconds": row["min_duration_seconds"]]
        }
    }
}
