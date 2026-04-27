import SwiftUI

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                ChatView()
            } else {
                OnboardingWelcomeView()
            }
        }
        .preferredColorScheme(.dark)
    }
}
