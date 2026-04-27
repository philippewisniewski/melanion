import SwiftUI
import Observation

@Observable
@MainActor
final class OnboardingViewModel {
    var profile = UserProfile()
    var currentPage: Int = 0

    func advance() {
        withAnimation(.easeInOut(duration: 0.3)) {
            currentPage += 1
        }
    }

    func saveAndFinish() {
        profile.save()
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
    }
}
