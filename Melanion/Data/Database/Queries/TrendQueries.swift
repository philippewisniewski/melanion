import Foundation
import GRDB

struct TimeOfDayQuery: QueryDefinition {
    let name = "time_of_day"
    let description = "Show run count and average pace grouped by time of day bracket: morning (5-9), midday (9-13), afternoon (13-17), evening (17-21), night (21-5)."
    let format: ResponseFormat = .rankedList

    func execute(db: Database, params: [String: String]) throws -> [QueryRow] {
        let sql = """
            SELECT CASE
                WHEN hour BETWEEN 5 AND 8 THEN 'Morning'
                WHEN hour BETWEEN 9 AND 12 THEN 'Midday'
                WHEN hour BETWEEN 13 AND 16 THEN 'Afternoon'
                WHEN hour BETWEEN 17 AND 20 THEN 'Evening'
                ELSE 'Night'
            END as time_of_day,
            COUNT(*) as run_count,
            ROUND(AVG(pace_seconds)) as avg_pace_seconds
            FROM runs
            GROUP BY time_of_day
            ORDER BY run_count DESC
            """
        return try Row.fetchAll(db, sql: sql, arguments: []).map { row in
            ["time_of_day": row["time_of_day"], "run_count": row["run_count"],
             "avg_pace_seconds": row["avg_pace_seconds"]]
        }
    }
}

struct SeasonalComparisonQuery: QueryDefinition {
    let name = "seasonal_comparison"
    let description = "Compare average pace, distance, and heart rate grouped by season: Spring, Summer, Autumn, Winter."
    let format: ResponseFormat = .rankedList

    func execute(db: Database, params: [String: String]) throws -> [QueryRow] {
        let sql = """
            SELECT CASE
                WHEN month IN (3,4,5) THEN 'Spring'
                WHEN month IN (6,7,8) THEN 'Summer'
                WHEN month IN (9,10,11) THEN 'Autumn'
                ELSE 'Winter'
            END as season,
            COUNT(*) as run_count,
            ROUND(AVG(pace_seconds)) as avg_pace_seconds,
            ROUND(AVG(distance_km),1) as avg_distance_km,
            ROUND(AVG(heart_rate_avg_bpm)) as avg_hr_bpm
            FROM runs
            GROUP BY season
            """
        return try Row.fetchAll(db, sql: sql, arguments: []).map { row in
            ["season": row["season"], "run_count": row["run_count"],
             "avg_pace_seconds": row["avg_pace_seconds"],
             "avg_distance_km": row["avg_distance_km"], "avg_hr_bpm": row["avg_hr_bpm"]]
        }
    }
}

struct VO2MaxTrendQuery: QueryDefinition {
    let name = "vo2_max_trend"
    let description = "Return VO2 max values over time from recovery data, showing trend."
    let format: ResponseFormat = .trend

    func execute(db: Database, params: [String: String]) throws -> [QueryRow] {
        let sql = """
            SELECT r.date, rec.vo2_max_ml_kg_min
            FROM runs r
            JOIN recovery rec ON rec.run_id = r.id
            WHERE rec.period = 'run_day' AND rec.vo2_max_ml_kg_min IS NOT NULL
            ORDER BY r.date ASC
            """
        return try Row.fetchAll(db, sql: sql, arguments: []).map { row in
            ["date": row["date"], "vo2_max_ml_kg_min": row["vo2_max_ml_kg_min"]]
        }
    }
}
