import SwiftUI

/// App entry: a minimal splash that pulls HealthKit data on load, then drops into the chat.
struct ContentView: View {
    @Environment(IntelligenceGate.self) private var gate
    @State private var didPull = false
    @State private var statusText = "Pulling your health data…"

    var body: some View {
        Group {
            if !gate.isAvailable {
                IntelligenceUnavailableView()
            } else if didPull {
                ChatView()
            } else {
                splash
                    .task { await pullData() }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var splash: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 14) {
                Text("Melanion")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text(statusText)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func pullData() async {
        if HealthKitPermissionManager.shared.isAvailable {
            try? await HealthKitPermissionManager.shared.requestPermissions()
        }
        _ = try? await HealthKitWorkoutFetcher().fetchRunningWorkouts()
        statusText = "Data pulled!"
        try? await Task.sleep(nanoseconds: 700_000_000)
        didPull = true
    }
}
