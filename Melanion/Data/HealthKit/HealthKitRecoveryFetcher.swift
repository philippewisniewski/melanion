import Foundation
import HealthKit

struct HealthKitRecoveryFetcher: Sendable {

    // MARK: - Public interface

    func fetchRecovery(for runDates: [Date]) async -> [RecoveryBundle] {
        var bundles: [RecoveryBundle] = []
        for date in runDates {
            guard let bundle = await fetchBundle(for: date) else { continue }
            bundles.append(bundle)
        }
        return bundles
    }

    // MARK: - Private helpers

    private var store: HKHealthStore {
        HealthKitPermissionManager.shared.store
    }

    private func fetchBundle(for runDate: Date) async -> RecoveryBundle? {
        let cal = Calendar.current

        // night_before: previous calendar day at 20:00 → run date at 06:00
        guard
            let prevDay = cal.date(byAdding: .day, value: -1, to: runDate),
            let nightStart = cal.date(bySettingHour: 20, minute: 0, second: 0, of: prevDay),
            let nightEnd   = cal.date(bySettingHour: 6,  minute: 0, second: 0, of: runDate),
            // run_day: run date at 06:00 → run date at 23:59:59
            let runDayStart = cal.date(bySettingHour: 6,  minute: 0,  second: 0,  of: runDate),
            let runDayEnd   = cal.date(bySettingHour: 23, minute: 59, second: 59, of: runDate),
            // day_after: day after run at 00:00 → day after at 23:59:59
            let nextDay    = cal.date(byAdding: .day, value: 1, to: runDate),
            let afterStart = cal.date(bySettingHour: 0,  minute: 0,  second: 0,  of: nextDay),
            let afterEnd   = cal.date(bySettingHour: 23, minute: 59, second: 59, of: nextDay)
        else { return nil }

        let nightInterval  = DateInterval(start: nightStart,  end: nightEnd)
        let runDayInterval = DateInterval(start: runDayStart, end: runDayEnd)
        let afterInterval  = DateInterval(start: afterStart,  end: afterEnd)

        async let nightMetrics  = fetchMetrics(period: .nightBefore, in: nightInterval)
        async let runDayMetrics = fetchMetrics(period: .runDay,      in: runDayInterval)
        async let afterMetrics  = fetchMetrics(period: .dayAfter,    in: afterInterval)

        let (night, run, after) = await (nightMetrics, runDayMetrics, afterMetrics)

        return RecoveryBundle(
            runStartedAt: runDate,
            nightBefore: night,
            runDay: run,
            dayAfter: after
        )
    }

    private func fetchMetrics(period: RecoveryPeriod, in window: DateInterval) async -> RecoveryMetrics {
        async let sleep    = fetchSleepHours(in: window)
        async let hrv      = fetchQuantity(.heartRateVariabilitySDNN,
                                          unit: HKUnit(from: "ms"),
                                          in: window)
        async let rhr      = fetchQuantity(.restingHeartRate,
                                          unit: HKUnit.count().unitDivided(by: .minute()),
                                          in: window)
        async let vo2      = fetchQuantity(.vo2Max,
                                          unit: HKUnit.literUnit(with: .milli)
                                              .unitDivided(by: HKUnit.gramUnit(with: .kilo)
                                                  .unitMultiplied(by: .minute())),
                                          in: window)
        async let hrr      = fetchQuantity(.heartRateRecoveryOneMinute,
                                          unit: HKUnit.count().unitDivided(by: .minute()),
                                          in: window)
        async let resp     = fetchQuantity(.respiratoryRate,
                                          unit: HKUnit.count().unitDivided(by: .minute()),
                                          in: window)
        async let wristT   = fetchQuantity(.appleSleepingWristTemperature,
                                          unit: HKUnit.degreeCelsius(),
                                          in: window)
        async let spo2     = fetchQuantity(.oxygenSaturation,
                                          unit: HKUnit.percent(),
                                          in: window)

        let (sleepHours, hrvVal, rhrVal, vo2Val, hrrVal, respVal, wristVal, spo2Val) =
            await (sleep, hrv, rhr, vo2, hrr, resp, wristT, spo2)

        return RecoveryMetrics(
            period: period,
            sleepDurationHours: sleepHours,
            hrvMs: hrvVal,
            restingHeartRateBpm: rhrVal.map { Int($0) },
            vo2MaxMlKgMin: vo2Val,
            heartRateRecoveryBpm: hrrVal.map { Int($0) },
            respiratoryRate: respVal,
            wristTemperatureC: wristVal,
            oxygenSaturationPct: spo2Val
        )
    }

    // MARK: - Quantity fetch

    private func fetchQuantity(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        in window: DateInterval
    ) async -> Double? {
        let quantityType = HKQuantityType(identifier)
        let predicate = HKQuery.predicateForSamples(
            withStart: window.start,
            end: window.end,
            options: [.strictStartDate, .strictEndDate]
        )
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                guard error == nil,
                      let sample = samples?.first as? HKQuantitySample
                else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: sample.quantity.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    // MARK: - Sleep fetch

    private func fetchSleepHours(in window: DateInterval) async -> Double? {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return nil
        }
        let predicate = HKQuery.predicateForSamples(
            withStart: window.start,
            end: window.end,
            options: [.strictStartDate, .strictEndDate]
        )

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                guard error == nil, let samples else {
                    continuation.resume(returning: nil)
                    return
                }
                let asleepValues: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                ]
                let totalSeconds = samples
                    .compactMap { $0 as? HKCategorySample }
                    .filter { asleepValues.contains($0.value) }
                    .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }

                if totalSeconds == 0 {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: totalSeconds / 3600.0)
                }
            }
            store.execute(query)
        }
    }
}
