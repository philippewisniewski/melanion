import Foundation
import HealthKit

struct HealthKitWorkoutFetcher {

    private let store: HKHealthStore

    init(store: HKHealthStore = HKHealthStore()) {
        self.store = store
    }

    // MARK: - Public API

    /// Fetches all running workouts, optionally filtered to those starting on or after `since`.
    /// Returns workouts sorted by startedAt descending.
    func fetchRunningWorkouts(since: Date? = nil) async throws -> [RunWorkout] {
        let workouts = try await queryRunningWorkouts(since: since)
        let mapped = workouts.compactMap { mapWorkout($0) }
        return mapped.sorted { $0.startedAt > $1.startedAt }
    }

    // MARK: - Query

    private func queryRunningWorkouts(since: Date?) async throws -> [HKWorkout] {
        try await withCheckedThrowingContinuation { continuation in
            var predicate = HKQuery.predicateForWorkouts(with: .running)
            if let since {
                let datePredicate = HKQuery.predicateForSamples(
                    withStart: since,
                    end: nil,
                    options: .strictStartDate
                )
                predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate, datePredicate])
            }

            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error))
                    return
                }
                let workouts = (samples as? [HKWorkout]) ?? []
                continuation.resume(returning: workouts)
            }

            store.execute(query)
        }
    }

    // MARK: - Mapping

    private func mapWorkout(_ workout: HKWorkout) -> RunWorkout? {
        let distanceMetres = workout.statistics(for: HKQuantityType(.distanceWalkingRunning))?
            .sumQuantity()?
            .doubleValue(for: .meter())

        guard let distanceMetres, distanceMetres > 0 else { return nil }

        let distanceKm = distanceMetres / 1_000.0
        let durationSeconds = Int(workout.duration)
        let paceSeconds = distanceKm > 0 ? Int(workout.duration / distanceKm) : 0

        // Heart rate
        let hrUnit = HKUnit.count().unitDivided(by: .minute())
        let heartRateAvgBpm = workout.statistics(for: HKQuantityType(.heartRate))?
            .averageQuantity()?
            .doubleValue(for: hrUnit)
            .map { Int($0) }
        let heartRateMinBpm = workout.statistics(for: HKQuantityType(.heartRate))?
            .minimumQuantity()?
            .doubleValue(for: hrUnit)
            .map { Int($0) }
        let heartRateMaxBpm = workout.statistics(for: HKQuantityType(.heartRate))?
            .maximumQuantity()?
            .doubleValue(for: hrUnit)
            .map { Int($0) }

        // NOTE: statistics(for: .stepCount) is only populated for workouts recorded directly
        // by Apple Watch. For third-party GPS watch imports (Garmin, COROS, Wahoo), this
        // returns nil. A future improvement could query per-sample runningGroundContactTime
        // over the workout's time range to derive cadence for all workout sources.
        let stepCount = workout.statistics(for: HKQuantityType(.stepCount))?
            .sumQuantity()?
            .doubleValue(for: .count())
        let cadenceStepsPerMin: Int?
        if let steps = stepCount, workout.duration > 0 {
            cadenceStepsPerMin = Int(steps / (workout.duration / 60.0))
        } else {
            cadenceStepsPerMin = nil
        }

        // Running form metrics
        let groundContactTimeMs = workout.statistics(for: HKQuantityType(.runningGroundContactTime))?
            .averageQuantity()?
            .doubleValue(for: HKUnit.secondUnit(with: .milli))

        let verticalOscillationCm = workout.statistics(for: HKQuantityType(.runningVerticalOscillation))?
            .averageQuantity()?
            .doubleValue(for: HKUnit.meterUnit(with: .centi))

        let strideLengthMetres = workout.statistics(for: HKQuantityType(.runningStrideLength))?
            .averageQuantity()?
            .doubleValue(for: .meter())

        // Power
        let runningPowerWatts = workout.statistics(for: HKQuantityType(.runningPower))?
            .averageQuantity()?
            .doubleValue(for: .watt())
            .map { Int($0) }

        // Active calories
        let activeCaloriesKcal = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?
            .sumQuantity()?
            .doubleValue(for: .kilocalorie())
            .map { Int($0) }

        return RunWorkout(
            startedAt: workout.startDate,
            durationSeconds: durationSeconds,
            distanceKm: distanceKm,
            paceSeconds: paceSeconds,
            heartRateAvgBpm: heartRateAvgBpm,
            heartRateMinBpm: heartRateMinBpm,
            heartRateMaxBpm: heartRateMaxBpm,
            cadenceStepsPerMin: cadenceStepsPerMin,
            groundContactTimeMs: groundContactTimeMs,
            verticalOscillationCm: verticalOscillationCm,
            strideLengthMetres: strideLengthMetres,
            runningPowerWatts: runningPowerWatts,
            activeCaloriesKcal: activeCaloriesKcal,
            elevationGainMetres: nil
        )
    }
}

