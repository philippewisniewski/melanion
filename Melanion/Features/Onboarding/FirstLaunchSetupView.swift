import SwiftUI

struct FirstLaunchSetupView: View {
    @Environment(IntelligenceGate.self) private var gate
    @State private var steps: [StepModel] = [
        StepModel(label: "Health permissions", icon: "heart.circle"),
        StepModel(label: "Verify your runs", icon: "figure.run.circle"),
        StepModel(label: "Check AI model", icon: "brain")
    ]

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 48) {
                Spacer()

                VStack(spacing: 8) {
                    Text("Setting up Melanion")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("This only happens once.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }

                VStack(spacing: 24) {
                    ForEach(steps) { step in
                        SetupStepRow(step: step) {
                            guard step.id == steps[1].id else { return }
                            steps[1].error = nil
                            withAnimation(.easeInOut(duration: 0.4)) {
                                steps[1].state = .active(progress: nil, detail: nil)
                            }
                            await verifyRuns()
                        }
                    }
                }
                .padding(.horizontal, 24)

                Spacer()

                if steps.allSatisfy({ if case .complete = $0.state { return true }; return false }) {
                    Button {
                        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                    } label: {
                        Text("Let's go")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 48)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .task { await runFullSetup() }
    }

    // MARK: - Setup orchestration

    private func runFullSetup() async {
        // Step 1 — Verify health permissions
        withAnimation(.easeInOut(duration: 0.4)) {
            steps[0].state = .active(progress: nil, detail: "Verifying…")
        }
        try? await Task.sleep(for: .seconds(1.2))
        withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
            steps[0].state = .complete(detail: "Granted")
        }

        try? await Task.sleep(for: .seconds(0.8))

        // Step 2 — Verify HealthKit data
        withAnimation(.easeInOut(duration: 0.4)) {
            steps[1].state = .active(progress: nil, detail: "Checking HealthKit…")
        }
        await verifyRuns()
        guard steps[1].error == nil else { return }

        try? await Task.sleep(for: .seconds(0.8))

        // Step 3 — AI model check
        withAnimation(.easeInOut(duration: 0.4)) {
            steps[2].state = .active(progress: nil, detail: "Checking…")
        }
        try? await Task.sleep(for: .seconds(1.2))
        gate.recheck()
        if gate.isAvailable {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                steps[2].state = .complete(detail: "Ready")
            }
        } else {
            withAnimation(.easeInOut(duration: 0.4)) {
                steps[2].error = gate.unavailableReason ?? "Apple Intelligence is not available."
                steps[2].state = .failed
            }
        }
    }

    private func verifyRuns() async {
        steps[1].error = nil

        do {
            let workouts = try await HealthKitWorkoutFetcher().fetchRunningWorkouts()
            let count = workouts.count

            await MilestoneDetector.shared.evaluateAfterSync()

            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                steps[1].state = .complete(detail: "\(count) runs found")
            }
        } catch {
            withAnimation(.easeInOut(duration: 0.4)) {
                steps[1].error = error.localizedDescription
                steps[1].state = .failed
            }
        }
    }
}

// MARK: - Step model

struct StepModel: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    var state: StepState = .pending
    var error: String?

    enum StepState: Equatable {
        case pending
        case active(progress: Double?, detail: String?)
        case complete(detail: String?)
        case failed
    }
}

// MARK: - SetupStepRow

struct SetupStepRow: View {
    let step: StepModel
    var onRetry: (() async -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            stateIcon
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 6) {
                Text(step.label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(labelColor)

                switch step.state {
                case .active(let progress, let detail):
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .contentTransition(.numericText())
                    }
                    ProgressView(value: progress)
                        .tint(Theme.accent)
                        .animation(.easeInOut(duration: 0.3), value: progress)

                case .complete(let detail):
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .transition(.blurReplace)
                    }

                case .failed:
                    if let error = step.error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    if let onRetry {
                        Button("Retry") { Task { await onRetry() } }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }

                case .pending:
                    EmptyView()
                }
            }

            Spacer()
        }
        .padding(16)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .animation(.easeInOut(duration: 0.4), value: step.state)
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch step.state {
        case .pending:
            Image(systemName: step.icon)
                .font(.system(size: 20))
                .foregroundStyle(Theme.textSecondary)

        case .active:
            ProgressView()
                .tint(Theme.accent)

        case .complete:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(Theme.accent)
                .transition(.scale.combined(with: .opacity))

        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(.red)
                .transition(.scale.combined(with: .opacity))
        }
    }

    private var labelColor: Color {
        switch step.state {
        case .pending:  Theme.textSecondary
        case .active:   Theme.textPrimary
        case .complete: Theme.accent
        case .failed:   .red
        }
    }
}
