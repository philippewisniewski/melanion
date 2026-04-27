import Foundation

struct KmSplit: Sendable {
    let km: Int               // 1-based (km 1, km 2 …)
    let splitSeconds: Int     // time taken for this km
    let elevationGainM: Double
    let elevationLossM: Double
}

/// Route enrichment for one run, keyed by the run's startedAt date
struct RouteData: Sendable {
    let runStartedAt: Date
    let startLat: Double
    let startLon: Double
    /// JSON-encoded [[Double]] array of [lat, lon] pairs, downsampled to ≤200 points
    let routePolyline: String
    let elevationGainMetres: Double
    let kmSplits: [KmSplit]
}
