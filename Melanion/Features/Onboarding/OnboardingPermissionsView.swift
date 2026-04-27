import SwiftUI

struct OnboardingPermissionsView: View {
    @Bindable var viewModel: OnboardingViewModel
    @State private var isRequesting = false
    @State private var errorMessage: String?
    @State private var showSetup = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 32) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(Theme.surface)
                            .frame(width: 96, height: 96)
                        Image(systemName: "heart.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(Theme.accent)
                    }

                    VStack(spacing: 12) {
                        Text("Connect Health")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)

                        Text("Melanion reads your running workouts, heart rate, recovery metrics, and GPS routes from Apple Health. Your data never leaves your iPhone.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }

                    // What we access
                    VStack(alignment: .leading, spacing: 10) {
                        PermissionRow(icon: "figure.run", text: "Running workouts & GPS routes")
                        PermissionRow(icon: "heart.fill", text: "Heart rate & recovery metrics")
                        PermissionRow(icon: "bed.double.fill", text: "Sleep duration & HRV")
                        PermissionRow(icon: "chart.line.uptrend.xyaxis", text: "VO₂ max & resting heart rate")
                    }
                    .padding(.horizontal, 24)

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                }

                Spacer()

                VStack(spacing: 12) {
                    HStack(spacing: 6) {
                        ForEach(0..<3) { i in
                            Capsule()
                                .fill(i == 2 ? Theme.accent : Theme.surface)
                                .frame(width: i == 2 ? 20 : 6, height: 6)
                        }
                    }

                    Button {
                        Task { await requestPermissions() }
                    } label: {
                        HStack(spacing: 8) {
                            if isRequesting {
                                ProgressView().tint(.white)
                            }
                            Text(isRequesting ? "Connecting…" : "Connect Health")
                                .font(.headline)
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(isRequesting)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
        }
        .fullScreenCover(isPresented: $showSetup) {
            FirstLaunchSetupView()
        }
    }

    private func requestPermissions() async {
        isRequesting = true
        errorMessage = nil
        do {
            try await HealthKitPermissionManager.shared.requestPermissions()
            viewModel.profile.save()   // persist profile; hasCompletedOnboarding set after setup
            showSetup = true
        } catch {
            errorMessage = "Could not connect to Health: \(error.localizedDescription)"
        }
        isRequesting = false
    }
}

struct PermissionRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Theme.accent)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
        }
    }
}
