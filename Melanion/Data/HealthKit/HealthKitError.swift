import Foundation

enum HealthKitError: Error, LocalizedError {
    case notAvailable
    case invalidType(String)
    case queryFailed(Error)
    case noData

    var errorDescription: String? {
        switch self {
        case .notAvailable: return "HealthKit is not available on this device."
        case .invalidType(let name): return "HealthKit type unavailable: \(name)"
        case .queryFailed(let e): return "HealthKit query failed: \(e.localizedDescription)"
        case .noData: return "No HealthKit data found."
        }
    }
}
