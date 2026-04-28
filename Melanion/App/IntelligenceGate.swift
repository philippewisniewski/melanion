import Foundation
import FoundationModels
import Observation

@Observable
@MainActor
final class IntelligenceGate {

    private(set) var availability: SystemLanguageModel.Availability

    var isAvailable: Bool {
        if case .available = availability { return true }
        return false
    }

    var unavailableReason: String? {
        guard case .unavailable(let reason) = availability else { return nil }
        switch reason {
        case .deviceNotEligible:
            return "Melanion requires Apple Intelligence, which needs an iPhone 15 Pro or later, or an iPad with M1 chip or later."
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence is supported on your device but needs to be enabled in Settings → Apple Intelligence & Siri."
        case .modelNotReady:
            return "Apple Intelligence is still downloading in the background. Check back in a few minutes."
        @unknown default:
            return "Apple Intelligence is not available on this device."
        }
    }

    var isDeviceEligible: Bool {
        guard case .unavailable(let reason) = availability else { return true }
        if case .deviceNotEligible = reason { return false }
        return true
    }

    var isSettingsFixable: Bool {
        guard case .unavailable(let reason) = availability else { return false }
        if case .appleIntelligenceNotEnabled = reason { return true }
        return false
    }

    init() {
        availability = SystemLanguageModel.default.availability
    }

    func recheck() {
        availability = SystemLanguageModel.default.availability
    }
}
