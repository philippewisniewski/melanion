import Foundation
import GRDB

struct HilliestRunsQuery: QueryDefinition {
    let name = "hilliest_runs"
    let description = "Return the top N runs with the most elevation gain."
    let format: ResponseFormat = .rankedList

    func execute(db: Database, params: [String: String]) throws -> [QueryRow] {
        let n = Int(params["n"] ?? "5") ?? 5
        let sql = """
            SELECT date, distance_km, elevation_gain_metres, pace_seconds
            FROM runs
            WHERE elevation_gain_metres IS NOT NULL
            ORDER BY elevation_gain_metres DESC
            LIMIT ?
            """
        return try Row.fetchAll(db, sql: sql, arguments: [n]).map { row in
            ["date": row["date"], "distance_km": row["distance_km"],
             "elevation_gain_metres": row["elevation_gain_metres"],
             "pace_seconds": row["pace_seconds"]]
        }
    }
}

struct ElevationVsPaceQuery: QueryDefinition {
    let name = "elevation_vs_pace"
    let description = "Compare average pace and grade-adjusted pace against elevation gain across all runs."
    let format: ResponseFormat = .trend

    func execute(db: Database, params: [String: String]) throws -> [QueryRow] {
        let sql = """
            SELECT date, elevation_gain_metres, pace_seconds, gap_seconds
            FROM runs
            WHERE elevation_gain_metres IS NOT NULL
            ORDER BY elevation_gain_metres ASC
            """
        return try Row.fetchAll(db, sql: sql, arguments: []).map { row in
            ["date": row["date"], "elevation_gain_metres": row["elevation_gain_metres"],
             "pace_seconds": row["pace_seconds"], "gap_seconds": row["gap_seconds"]]
        }
    }
}
