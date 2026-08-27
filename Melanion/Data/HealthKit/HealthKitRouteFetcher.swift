import Foundation
import HealthKit
import CoreLocation
import os

/// Fetches the GPS route for a workout and derives split / elevation enrichment.
/// Mirrors the per-km split logic from the Python `parse_gpx.py` pipeline, ported to
/// HealthKit `HKWorkoutRoute` locations.
struct HealthKitRouteFetcher {

    private let store: HKHealthStore

    init(store: HKHealthStore = HealthKitPermissionManager.shared.store) {
        self.store = store
    }

    // MARK: - Public API

    /// Fetches the GPS route for a single workout and derives split/elevation enrichment.
    /// Returns nil if the workout has no route (e.g. indoor/treadmill, or watch didn't record GPS).
    func fetchRouteData(for workout: HKWorkout) async -> RouteData? {
        guard let locations = await fetchRouteLocations(for: workout), locations.count >= 2 else {
            return nil
        }
        let kmSplits = Self.computeKmSplits(locations: locations)
        guard !kmSplits.isEmpty else { return nil }

        let start = locations.first!
        let elevationGain = kmSplits.reduce(0.0) { $0 + $1.elevationGainM }

        // Downsample polyline to ≤200 points for storage / map display.
        let polyline = Self.downsample(locations: locations, maxPoints: 200)

        return RouteData(
            runStartedAt: workout.startDate,
            startLat: start.coordinate.latitude,
            startLon: start.coordinate.longitude,
            routePolyline: polyline,
            elevationGainMetres: elevationGain,
            kmSplits: kmSplits
        )
    }

    // MARK: - Route location fetch

    private func fetchRouteLocations(for workout: HKWorkout) async -> [CLLocation]? {
        let routes: [HKWorkoutRoute]
        do {
            routes = try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(
                    sampleType: HKSeriesType.workoutRoute(),
                    predicate: HKQuery.predicateForObjects(from: workout),
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: nil
                ) { _, samples, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: (samples as? [HKWorkoutRoute]) ?? [])
                    }
                }
                store.execute(query)
            }
        } catch {
            return nil
        }

        guard let route = routes.first else { return nil }

        return await withCheckedContinuation { continuation in
            struct RouteState {
                var points: [CLLocation] = []
                var resumed = false
            }
            let lock = OSAllocatedUnfairLock<RouteState>(initialState: RouteState())
            let query = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                lock.withLock { state in
                    if error != nil {
                        guard !state.resumed else { return }
                        state.resumed = true
                        continuation.resume(returning: state.points)
                        return
                    }
                    state.points.append(contentsOf: locations ?? [])
                    if done {
                        guard !state.resumed else { return }
                        state.resumed = true
                        continuation.resume(returning: state.points)
                    }
                }
            }
            store.execute(query)
        }
    }

    // MARK: - Split computation

    /// Computes per-kilometre splits (and per-km elevation gain/loss) from an ordered GPS track.
    /// Locations are sorted by timestamp; cumulative distance is walked and each 1 km boundary is
    /// interpolated in time to derive the seconds taken for that kilometre.
    static func computeKmSplits(locations: [CLLocation]) -> [KmSplit] {
        let sorted = locations.sorted { $0.timestamp < $1.timestamp }
        guard sorted.count >= 2 else { return [] }

        // Cumulative distance + time at each point.
        var cumDist: [Double] = [0]
        var times: [TimeInterval] = [sorted[0].timestamp.timeIntervalSinceReferenceDate]
        for i in 1..<sorted.count {
            let d = sorted[i - 1].distance(from: sorted[i])
            cumDist.append(cumDist.last! + max(0, d))
            times.append(sorted[i].timestamp.timeIntervalSinceReferenceDate)
        }

        let total = cumDist.last!
        let fullKm = Int(total / 1000)
        guard fullKm >= 1 else { return [] }

        var splits: [KmSplit] = []
        var prevBoundaryTime = times[0]
        var prevBoundaryDist = 0.0

        for km in 1...fullKm {
            let target = Double(km) * 1000.0
            guard let seg = (1..<cumDist.count).first(where: { cumDist[$0] >= target }) else { break }
            let d0 = cumDist[seg - 1], d1 = cumDist[seg]
            let t0 = times[seg - 1], t1 = times[seg]
            let frac = (d1 > d0) ? (target - d0) / (d1 - d0) : 0
            let boundaryTime = t0 + frac * (t1 - t0)

            let splitSeconds = Int(round(boundaryTime - prevBoundaryTime))
            let (gain, loss) = elevationChange(
                in: sorted, fromDist: prevBoundaryDist, toDist: target, cumDist: cumDist
            )
            splits.append(
                KmSplit(
                    km: km,
                    splitSeconds: max(0, splitSeconds),
                    elevationGainM: gain,
                    elevationLossM: loss
                )
            )

            prevBoundaryTime = boundaryTime
            prevBoundaryDist = target
        }
        return splits
    }

    private static func elevationChange(
        in locations: [CLLocation],
        fromDist startDist: Double,
        toDist endDist: Double,
        cumDist: [Double]
    ) -> (gain: Double, loss: Double) {
        var gain = 0.0, loss = 0.0
        for i in 1..<locations.count {
            let segStart = max(cumDist[i - 1], startDist)
            let segEnd = min(cumDist[i], endDist)
            guard segEnd > segStart else { continue }
            let delta = locations[i].altitude - locations[i - 1].altitude
            if delta > 0 { gain += delta } else { loss += -delta }
        }
        return (gain, loss)
    }

    // MARK: - Polyline downsample

    private static func downsample(locations: [CLLocation], maxPoints: Int) -> String {
        let points: [CLLocation]
        if locations.count <= maxPoints {
            points = locations
        } else {
            let stride = Double(locations.count) / Double(maxPoints)
            var out: [CLLocation] = []
            for i in 0..<maxPoints {
                let idx = min(locations.count - 1, Int(Double(i) * stride))
                out.append(locations[idx])
            }
            points = out
        }
        let encoded = points.map { "[\($0.coordinate.latitude),\($0.coordinate.longitude)]" }
        return "[" + encoded.joined(separator: ",") + "]"
    }
}
