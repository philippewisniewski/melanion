import Foundation

enum RecoveryPeriod: String, Sendable {
    case nightBefore = "night_before"
    case runDay      = "run_day"
    case dayAfter    = "day_after"
}

struct RecoveryMetrics: Sendable {
    let period: RecoveryPeriod
    let sleepDurationHours: Double?
    let hrvMs: Double?
    let restingHeartRateBpm: Int?
    let vo2MaxMlKgMin: Double?
    let heartRateRecoveryBpm: Int?
    let respiratoryRate: Double?
    let wristTemperatureC: Double?
    let oxygenSaturationPct: Double?
}

/// All recovery periods associated with one run, keyed by the run's startedAt date
struct RecoveryBundle: Sendable {
    let runStartedAt: Date
    let nightBefore: RecoveryMetrics
    let runDay: RecoveryMetrics
    let dayAfter: RecoveryMetrics
}
