import SwiftUI

struct OnboardingWelcomeView: View {
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            Text("Onboarding")
                .foregroundStyle(Theme.textPrimary)
        }
    }
}
