import Foundation

struct RunWorkout: Sendable {
    let startedAt: Date
    let durationSeconds: Int
    let distanceKm: Double
    /// Pace in integer seconds per km — e.g. 270 = 4:30/km. Derived from duration ÷ distance, not from a HealthKit field.
    let paceSeconds: Int
    let heartRateAvgBpm: Int?
    let heartRateMinBpm: Int?
    let heartRateMaxBpm: Int?
    let cadenceStepsPerMin: Int?
    let groundContactTimeMs: Double?
    let verticalOscillationCm: Double?
    let strideLengthMetres: Double?
    let runningPowerWatts: Int?
    let activeCaloriesKcal: Int?
    /// Elevation gain — populated from HealthKit during fetch
    let elevationGainMetres: Double?
    /// Per-km split paces in integer seconds (e.g. 303 = 5:03/km), one entry per km of the run.
    /// Populated from a HealthKit route via HealthKitRouteFetcher; nil when no route exists.
    var splitsSecondsPerKm: [Int]? = nil
}
