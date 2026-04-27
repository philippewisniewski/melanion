import SwiftUI

struct FirstLaunchSetupView: View {
    @State private var pipeline = SeedingPipeline()
    @State private var downloader = ModelDownloadManager()
    @State private var setupPhase: SetupPhase = .idle
    @State private var seedError: String?
    @State private var downloadError: String?

    enum SetupPhase {
        case idle, seeding, downloading, complete
    }

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
                    SetupStepRow(
                        icon: "checkmark.circle.fill",
                        label: "Health permissions granted",
                        subLabel: nil,
                        state: .complete,
                        progress: nil
                    )

                    SetupStepRow(
                        icon: "figure.run.circle",
                        label: setupPhase == .seeding ? seedingLabel : "Import your runs",
                        subLabel: pipeline.progress.map { "\($0.processed) of \($0.total)" },
                        state: stepState(for: .seeding),
                        progress: seedingProgress,
                        errorMessage: seedError,
                        onRetry: { Task { await runSeeding() } }
                    )

                    SetupStepRow(
                        icon: "cpu",
                        label: "Download AI model",
                        subLabel: downloadSubLabel,
                        state: stepState(for: .downloading),
                        progress: downloader.downloadProgress,
                        errorMessage: downloadError,
                        onRetry: { downloader.startDownload() }
                    )
                }
                .padding(.horizontal, 24)

                Spacer()

                if setupPhase == .complete {
                    Button {
                        // hasCompletedOnboarding is already true — ContentView will switch to ChatView
                        // Dismiss this sheet by removing it from the hierarchy
                        UserDefaults.standard.set(true, forKey: "setupComplete")
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
                    .transition(.opacity)
                }
            }
        }
        .task { await runFullSetup() }
        .onChange(of: downloader.state) { _, newState in
            if newState == .complete {
                withAnimation { setupPhase = .complete }
            } else if case .failed(let msg) = newState {
                downloadError = msg
            }
        }
    }

    // MARK: - Setup orchestration

    private func runFullSetup() async {
        await runSeeding()
        await runDownload()
    }

    private func runSeeding() async {
        seedError = nil
        withAnimation { setupPhase = .seeding }
        await pipeline.seed()
        if let error = pipeline.lastError {
            seedError = error
        } else {
            withAnimation { setupPhase = .downloading }
            await runDownload()
        }
    }

    private func runDownload() async {
        downloadError = nil
        if ModelStore.isModelDownloaded {
            withAnimation { setupPhase = .complete }
            return
        }
        downloader.startDownload()
    }

    // MARK: - Computed helpers

    private var seedingLabel: String {
        guard let p = pipeline.progress else { return "Import your runs" }
        switch p.phase {
        case .fetchingWorkouts: return "Fetching workouts…"
        case .fetchingRecovery: return "Fetching recovery data…"
        case .fetchingRoutes:   return "Fetching routes…"
        case .writing:          return "Writing to database…"
        case .complete:         return "Runs imported"
        }
    }

    private var seedingProgress: Double? {
        guard let p = pipeline.progress, p.total > 0 else { return nil }
        return Double(p.processed) / Double(p.total)
    }

    private var downloadSubLabel: String? {
        guard downloader.totalBytes > 0 else { return nil }
        let downloaded = ByteCountFormatter.string(fromByteCount: downloader.downloadedBytes, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: downloader.totalBytes, countStyle: .file)
        return "\(downloaded) of \(total)"
    }

    private func stepState(for phase: SetupPhase) -> SetupStepRow.StepState {
        switch phase {
        case .idle: return .pending
        case .seeding:
            if setupPhase == .seeding { return pipeline.isRunning ? .active : (seedError != nil ? .failed : .complete) }
            if setupPhase == .downloading || setupPhase == .complete { return .complete }
            return .pending
        case .downloading:
            if setupPhase == .downloading {
                return downloadError != nil ? .failed : .active
            }
            if setupPhase == .complete { return .complete }
            return .pending
        case .complete: return .pending
        }
    }
}

// MARK: - SetupStepRow

struct SetupStepRow: View {
    enum StepState { case pending, active, complete, failed }

    let icon: String
    let label: String
    let subLabel: String?
    let state: StepState
    var progress: Double?
    var errorMessage: String? = nil
    var onRetry: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            stateIcon
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 6) {
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(labelColor)

                if let sub = subLabel {
                    Text(sub)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }

                if state == .active, let prog = progress {
                    ProgressView(value: prog)
                        .tint(Theme.accent)
                        .animation(.easeInOut, value: prog)
                }

                if let error = errorMessage, state == .failed {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                    if let retry = onRetry {
                        Button("Retry", action: retry)
                            .font(.caption)
                            .foregroundStyle(Theme.accent)
                    }
                }
            }

            Spacer()
        }
        .padding(16)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch state {
        case .pending:
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 32, height: 32)
        case .active:
            ProgressView()
                .tint(Theme.accent)
                .frame(width: 32, height: 32)
        case .complete:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(Theme.accent)
                .frame(width: 32, height: 32)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(.red)
                .frame(width: 32, height: 32)
        }
    }

    private var labelColor: Color {
        switch state {
        case .pending: return Theme.textSecondary
        case .active:  return Theme.textPrimary
        case .complete: return Theme.accent
        case .failed:  return .red
        }
    }
}
