import Foundation
import HealthKit
import CoreLocation

struct HealthKitRouteFetcher: Sendable {

    // MARK: - Public interface

    func fetchRoutes(for workouts: [HKWorkout]) async -> [RouteData] {
        var results: [RouteData] = []
        for workout in workouts {
            guard let route = await fetchRoute(for: workout) else { continue }
            results.append(route)
        }
        return results
    }

    // MARK: - Private helpers

    private var store: HKHealthStore {
        HealthKitPermissionManager.shared.store
    }

    private func fetchRoute(for workout: HKWorkout) async -> RouteData? {
        guard let hkRoute = await fetchWorkoutRoute(for: workout) else { return nil }
        guard let locations = await fetchLocations(from: hkRoute), !locations.isEmpty else { return nil }

        let first = locations[0]
        let startLat = first.coordinate.latitude
        let startLon = first.coordinate.longitude

        let totalElevationGain = computeTotalElevationGain(from: locations)
        let kmSplits = computeKmSplits(from: locations)
        let polyline = encodePolyline(from: locations)

        return RouteData(
            runStartedAt: workout.startDate,
            startLat: startLat,
            startLon: startLon,
            routePolyline: polyline,
            elevationGainMetres: totalElevationGain,
            kmSplits: kmSplits
        )
    }

    // MARK: - HKWorkoutRoute fetch

    private func fetchWorkoutRoute(for workout: HKWorkout) async -> HKWorkoutRoute? {
        let predicate = HKQuery.predicateForObjects(from: workout)

        // One-shot form of HKAnchoredObjectQuery (no updateHandler) fires the completionHandler
        // exactly once, so no double-resume guard is needed.
        return await withCheckedContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: HKSeriesType.workoutRoute(),
                predicate: predicate,
                anchor: nil,
                limit: HKObjectQueryNoLimit
            ) { _, samples, _, _, error in
                if error != nil {
                    continuation.resume(returning: nil)
                    return
                }
                let route = samples?.first as? HKWorkoutRoute
                continuation.resume(returning: route)
            }

            store.execute(query)
        }
    }

    // MARK: - CLLocation stream

    private func fetchLocations(from route: HKWorkoutRoute) async -> [CLLocation]? {
        // Box mutable state to satisfy Swift 6 Sendable requirements.
        // HealthKit delivers route callbacks serially on its own queue, so no lock is needed —
        // @unchecked Sendable is safe here because we rely on that guarantee.
        final class RouteState: @unchecked Sendable {
            var accumulated: [CLLocation] = []
            var hasResumed = false
        }
        let state = RouteState()

        return await withCheckedContinuation { continuation in
            let query = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                if error != nil {
                    guard !state.hasResumed else { return }
                    state.hasResumed = true
                    continuation.resume(returning: nil)
                    return
                }
                if let locations {
                    state.accumulated.append(contentsOf: locations)
                }
                if done {
                    guard !state.hasResumed else { return }
                    state.hasResumed = true
                    continuation.resume(returning: state.accumulated.isEmpty ? nil : state.accumulated)
                }
            }
            store.execute(query)
        }
    }

    // MARK: - Elevation

    private func computeTotalElevationGain(from locations: [CLLocation]) -> Double {
        var gain = 0.0
        for i in 1 ..< locations.count {
            let delta = locations[i].altitude - locations[i - 1].altitude
            if delta > 0 { gain += delta }
        }
        return gain
    }

    // MARK: - Km splits

    private func computeKmSplits(from locations: [CLLocation]) -> [KmSplit] {
        guard locations.count > 1 else { return [] }

        var splits: [KmSplit] = []
        var kmNumber = 1
        var cumulativeDistance = 0.0
        var splitStartTime = locations[0].timestamp
        var splitElevGain = 0.0
        var splitElevLoss = 0.0
        let threshold = 1000.0 // metres per km

        for i in 1 ..< locations.count {
            let segment = locations[i].distance(from: locations[i - 1])
            cumulativeDistance += segment

            let altDelta = locations[i].altitude - locations[i - 1].altitude
            if altDelta > 0 {
                splitElevGain += altDelta
            } else {
                splitElevLoss += abs(altDelta)
            }

            // NOTE: If a GPS gap spans more than 1 km (tunnel, indoor, signal loss), this produces
            // a split with near-zero elapsed time. Acceptable for outdoor running data; consumers
            // should filter splits with elapsed < 30s as likely GPS artefacts.
            if cumulativeDistance >= Double(kmNumber) * threshold {
                let elapsed = locations[i].timestamp.timeIntervalSince(splitStartTime)
                splits.append(KmSplit(
                    km: kmNumber,
                    splitSeconds: Int(elapsed),
                    elevationGainM: splitElevGain,
                    elevationLossM: splitElevLoss
                ))
                kmNumber += 1
                splitStartTime = locations[i].timestamp
                splitElevGain = 0.0
                splitElevLoss = 0.0
            }
        }
        return splits
    }

    // MARK: - Polyline encoding

    private func encodePolyline(from locations: [CLLocation]) -> String {
        let count = locations.count
        let stride = max(1, count / 200)
        var sampled: [[Double]] = []
        var index = 0
        while index < count {
            let loc = locations[index]
            sampled.append([loc.coordinate.latitude, loc.coordinate.longitude])
            index += stride
        }
        // Always include last point for continuity
        if let last = locations.last {
            let lastPair = [last.coordinate.latitude, last.coordinate.longitude]
            if sampled.last != lastPair {
                sampled.append(lastPair)
            }
        }

        guard let data = try? JSONEncoder().encode(sampled),
              let json = String(data: data, encoding: .utf8)
        else { return "[]" }
        return json
    }
}
