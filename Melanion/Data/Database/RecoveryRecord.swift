import Foundation
import GRDB

struct RecoveryRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "recovery"

    var id: Int64?
    var runId: Int64              // FK → runs(id)
    var period: String            // "night_before" | "run_day" | "day_after"
    var sleepDurationHours: Double?
    var hrvMs: Double?
    var restingHeartRateBpm: Int?
    var vo2MaxMlKgMin: Double?
    var heartRateRecoveryBpm: Int?
    var respiratoryRate: Double?
    var wristTemperatureC: Double?
    var oxygenSaturationPct: Double?
}

extension RecoveryRecord: TableRecord {
    enum Columns: String, ColumnExpression {
        case id, runId = "run_id", period
        case sleepDurationHours = "sleep_duration_hours"
        case hrvMs = "hrv_ms", restingHeartRateBpm = "resting_heart_rate_bpm"
        case vo2MaxMlKgMin = "vo2_max_ml_kg_min"
        case heartRateRecoveryBpm = "heart_rate_recovery_bpm"
        case respiratoryRate = "respiratory_rate"
        case wristTemperatureC = "wrist_temperature_c"
        case oxygenSaturationPct = "oxygen_saturation_pct"
    }

    static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase
    static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
}
