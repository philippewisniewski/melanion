import SwiftUI

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(IntelligenceGate.self) private var gate

    var body: some View {
        Group {
            if !hasCompletedOnboarding {
                OnboardingWelcomeView()
            } else if !gate.isAvailable {
                IntelligenceUnavailableView()
            } else {
                NavigationStack {
                    ChatView()
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
