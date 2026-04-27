import HealthKit

final class HealthKitPermissionManager: Sendable {
    static let shared = HealthKitPermissionManager()

    let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    @MainActor
    func requestPermissions() async throws {
        guard isAvailable else { throw HealthKitError.notAvailable }
        let readTypes = try buildReadTypes()
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    private func buildReadTypes() throws -> Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
        ]

        let quantityIdentifiers: [HKQuantityTypeIdentifier] = [
            .distanceWalkingRunning,
            .heartRate,
            .runningSpeed,
            .stepCount,
            .runningGroundContactTime,
            .runningVerticalOscillation,
            .runningStrideLength,
            .runningPower,
            .activeEnergyBurned,
            .flightsClimbed,
            .heartRateVariabilitySDNN,
            .restingHeartRate,
            .vo2Max,
            .oxygenSaturation,
            .respiratoryRate,
            .appleSleepingWristTemperature,
            .heartRateRecoveryOneMinute,
        ]
        for id in quantityIdentifiers {
            types.insert(HKQuantityType(id))
        }
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw HealthKitError.invalidType("sleepAnalysis")
        }
        types.insert(sleepType)
        return types
    }
}
