import SwiftUI

struct IntelligenceUnavailableView: View {
    @Environment(IntelligenceGate.self) private var gate
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                Image(systemName: "brain")
                    .font(.system(size: 64))
                    .foregroundStyle(Theme.accent)

                VStack(spacing: 12) {
                    Text("Apple Intelligence Required")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)

                    if let reason = gate.unavailableReason {
                        Text(reason)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                }

                if gate.isSettingsFixable {
                    Button {
                        if let url = URL(string: "App-prefs:") {
                            openURL(url)
                        }
                    } label: {
                        Text("Open Settings")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal, 32)
                }

                Spacer()
            }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                gate.recheck()
            }
        }
    }
}
