import Foundation
import GRDB

struct RunRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "runs"

    var id: Int64?
    var startedAt: String         // ISO 8601, unique — used as upsert key
    var date: String              // YYYY-MM-DD
    var year: Int
    var month: Int
    var hour: Int
    var distanceKm: Double
    var durationSeconds: Int
    var paceSeconds: Int          // integer seconds/km — e.g. 270 = 4:30/km
    var heartRateAvgBpm: Int?
    var heartRateMinBpm: Int?
    var heartRateMaxBpm: Int?
    var cadenceStepsPerMin: Int?
    var groundContactTimeMs: Double?
    var verticalOscillationCm: Double?
    var strideLengthMetres: Double?
    var runningPowerWatts: Int?
    var activeCaloriesKcal: Int?
    var elevationGainMetres: Double?
    var gapSeconds: Int?          // grade-adjusted pace in seconds/km
    var pacingPattern: String?    // "negative" | "positive" | "even"
    var startLat: Double?
    var startLon: Double?
    var routePolyline: String?
}

// GRDB CodingKeys mapping: Swift camelCase → SQL snake_case
extension RunRecord: TableRecord {
    enum Columns: String, ColumnExpression {
        case id, startedAt = "started_at", date, year, month, hour
        case distanceKm = "distance_km", durationSeconds = "duration_seconds"
        case paceSeconds = "pace_seconds", heartRateAvgBpm = "heart_rate_avg_bpm"
        case heartRateMinBpm = "heart_rate_min_bpm", heartRateMaxBpm = "heart_rate_max_bpm"
        case cadenceStepsPerMin = "cadence_steps_per_min"
        case groundContactTimeMs = "ground_contact_time_ms"
        case verticalOscillationCm = "vertical_oscillation_cm"
        case strideLengthMetres = "stride_length_metres"
        case runningPowerWatts = "running_power_watts"
        case activeCaloriesKcal = "active_calories_kcal"
        case elevationGainMetres = "elevation_gain_metres"
        case gapSeconds = "gap_seconds"
        case pacingPattern = "pacing_pattern"
        case startLat = "start_lat", startLon = "start_lon"
        case routePolyline = "route_polyline"
    }

    static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase
    static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
}
