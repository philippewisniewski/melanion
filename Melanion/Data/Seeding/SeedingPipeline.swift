import Foundation
import HealthKit
import GRDB

// MARK: - SeedingProgress

struct SeedingProgress: Sendable {
    enum Phase: Sendable {
        case fetchingWorkouts
        case fetchingRecovery
        case fetchingRoutes
        case writing
        case complete
    }
    let phase: Phase
    let total: Int
    let processed: Int
}

// MARK: - SeedingPipeline

@Observable @MainActor
final class SeedingPipeline {

    // MARK: - Published state

    var progress: SeedingProgress?
    var isRunning: Bool = false
    var lastError: String?

    // MARK: - Entry point

    func seed() async {
        guard !isRunning else { return }
        isRunning = true
        lastError = nil
        progress = SeedingProgress(phase: .fetchingWorkouts, total: 0, processed: 0)

        do {
            // Step 1 — Fetch RunWorkout values from HealthKit
            let workouts = try await HealthKitWorkoutFetcher().fetchRunningWorkouts()
            let total = workouts.count
            progress = SeedingProgress(phase: .fetchingWorkouts, total: total, processed: total)

            // Step 2 — Fetch recovery bundles for all run dates
            progress = SeedingProgress(phase: .fetchingRecovery, total: total, processed: 0)
            let runDates = workouts.map(\.startedAt)
            let recoveryBundles = await HealthKitRecoveryFetcher().fetchRecovery(for: runDates)
            let recoveryByDate = Dictionary(
                uniqueKeysWithValues: recoveryBundles.map { ($0.runStartedAt, $0) }
            )
            progress = SeedingProgress(phase: .fetchingRecovery, total: total, processed: total)

            // Step 3 — Fetch routes (requires raw HKWorkout objects)
            progress = SeedingProgress(phase: .fetchingRoutes, total: total, processed: 0)
            let rawWorkouts = try await fetchRawWorkouts()
            let routeDataList = await HealthKitRouteFetcher().fetchRoutes(for: rawWorkouts)
            let routeByDate = Dictionary(
                uniqueKeysWithValues: routeDataList.map { ($0.runStartedAt, $0) }
            )
            progress = SeedingProgress(phase: .fetchingRoutes, total: total, processed: total)

            // Step 4 — Write everything to GRDB in a single transaction
            progress = SeedingProgress(phase: .writing, total: total, processed: 0)
            try await writeToDatabase(
                workouts: workouts,
                recoveryByDate: recoveryByDate,
                routeByDate: routeByDate
            )
            progress = SeedingProgress(phase: .complete, total: total, processed: total)

        } catch {
            lastError = error.localizedDescription
        }

        isRunning = false
    }

    // MARK: - Database write

    private func writeToDatabase(
        workouts: [RunWorkout],
        recoveryByDate: [Date: RecoveryBundle],
        routeByDate: [Date: RouteData]
    ) async throws {
        let db = DatabaseManager.shared.db
        // Pre-compute records on MainActor before entering the synchronous write closure.
        let preparedRecords: [(RunRecord, RecoveryBundle?, RouteData?)] = workouts.map { workout in
            let route = routeByDate[workout.startedAt]
            let runRecord = makeRunRecord(from: workout, route: route)
            let bundle = recoveryByDate[workout.startedAt]
            return (runRecord, bundle, route)
        }
        let total = workouts.count

        try await db.write { database in
            for (index, (runRecord, bundle, route)) in preparedRecords.enumerated() {
                do {
                    // Upsert on started_at (the unique column)
                    try runRecord.upsert(database)
                    let savedRun = try RunRecord
                        .filter(Column("started_at") == runRecord.startedAt)
                        .fetchOne(database)!
                    let runId = savedRun.id!

                    // Write recovery rows (one per period)
                    if let bundle {
                        for metrics in [bundle.nightBefore, bundle.runDay, bundle.dayAfter] {
                            let rec = RecoveryRecord(
                                id: nil,
                                runId: runId,
                                period: metrics.period.rawValue,
                                sleepDurationHours: metrics.sleepDurationHours,
                                hrvMs: metrics.hrvMs,
                                restingHeartRateBpm: metrics.restingHeartRateBpm,
                                vo2MaxMlKgMin: metrics.vo2MaxMlKgMin,
                                heartRateRecoveryBpm: metrics.heartRateRecoveryBpm,
                                respiratoryRate: metrics.respiratoryRate,
                                wristTemperatureC: metrics.wristTemperatureC,
                                oxygenSaturationPct: metrics.oxygenSaturationPct
                            )
                            try rec.insert(database, onConflict: .replace)
                        }
                    }

                    // Write route splits — delete existing first, then insert fresh
                    if let route {
                        try RouteSplitRecord
                            .filter(Column("run_id") == runId)
                            .deleteAll(database)
                        for split in route.kmSplits {
                            let splitRecord = RouteSplitRecord(
                                id: nil,
                                runId: runId,
                                km: split.km,
                                splitSeconds: split.splitSeconds,
                                elevationGainM: split.elevationGainM,
                                elevationLossM: split.elevationLossM
                            )
                            try splitRecord.insert(database)
                        }
                    }
                } catch {
                    print("[SeedingPipeline] skipping workout: \(error)")
                }

                // Update progress on MainActor after each workout
                let processed = index + 1
                Task { @MainActor in
                    self.progress = SeedingProgress(
                        phase: .writing,
                        total: total,
                        processed: processed
                    )
                }
            }
        }
    }

    // MARK: - Raw HKWorkout fetch

    private func fetchRawWorkouts() async throws -> [HKWorkout] {
        let store = HealthKitPermissionManager.shared.store
        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForWorkouts(with: .running)
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

    // MARK: - Mapping helpers

    private func makeRunRecord(from workout: RunWorkout, route: RouteData?) -> RunRecord {
        let cal = Calendar.current
        let components = cal.dateComponents([.year, .month, .hour], from: workout.startedAt)
        let isoFormatter = ISO8601DateFormatter()
        let startedAt = isoFormatter.string(from: workout.startedAt)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let date = dateFormatter.string(from: workout.startedAt)

        let splits = route?.kmSplits ?? []
        let pacingPattern = computePacingPattern(from: splits)
        let gapSeconds = computeGAP(paceSeconds: workout.paceSeconds, splits: splits)

        return RunRecord(
            id: nil,
            startedAt: startedAt,
            date: date,
            year: components.year ?? 0,
            month: components.month ?? 0,
            hour: components.hour ?? 0,
            distanceKm: workout.distanceKm,
            durationSeconds: workout.durationSeconds,
            paceSeconds: workout.paceSeconds,
            heartRateAvgBpm: workout.heartRateAvgBpm,
            heartRateMinBpm: workout.heartRateMinBpm,
            heartRateMaxBpm: workout.heartRateMaxBpm,
            cadenceStepsPerMin: workout.cadenceStepsPerMin,
            groundContactTimeMs: workout.groundContactTimeMs,
            verticalOscillationCm: workout.verticalOscillationCm,
            strideLengthMetres: workout.strideLengthMetres,
            runningPowerWatts: workout.runningPowerWatts,
            activeCaloriesKcal: workout.activeCaloriesKcal,
            elevationGainMetres: route?.elevationGainMetres ?? workout.elevationGainMetres,
            gapSeconds: gapSeconds,
            pacingPattern: pacingPattern,
            startLat: route?.startLat,
            startLon: route?.startLon,
            routePolyline: route?.routePolyline
        )
    }

    // MARK: - Pacing pattern

    private func computePacingPattern(from splits: [KmSplit]) -> String? {
        guard splits.count >= 2 else { return nil }
        let half = splits.count / 2
        let firstHalfAvg = splits[..<half].map(\.splitSeconds).reduce(0, +) / half
        let secondHalfAvg = splits[half...].map(\.splitSeconds).reduce(0, +) / (splits.count - half)
        let diff = secondHalfAvg - firstHalfAvg
        if diff < -5 { return "negative" }
        if diff > 5  { return "positive" }
        return "even"
    }

    // MARK: - Grade-adjusted pace

    private func computeGAP(paceSeconds: Int, splits: [KmSplit]) -> Int? {
        guard !splits.isEmpty else { return nil }
        let totalGain = splits.map(\.elevationGainM).reduce(0, +)
        let totalLoss = splits.map(\.elevationLossM).reduce(0, +)
        let totalDistanceM = Double(splits.count) * 1000.0
        let gradePct = (totalGain - totalLoss) / totalDistanceM * 100
        let adjustment: Double
        if gradePct > 0 {
            adjustment = gradePct * 8   // uphill: add 8s per km per 1% grade
        } else {
            adjustment = gradePct * 5   // downhill: subtract 5s per km per 1% grade
        }
        return max(0, paceSeconds + Int(adjustment))
    }
}
