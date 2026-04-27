import SwiftUI

struct OnboardingWelcomeView: View {
    @State private var viewModel = OnboardingViewModel()

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 24) {
                    // App icon / logo area
                    ZStack {
                        Circle()
                            .fill(Theme.surface)
                            .frame(width: 96, height: 96)
                        Text("M")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.accent)
                    }

                    VStack(spacing: 8) {
                        Text("Melanion")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)

                        Text("Your personal running coach,\npowered entirely on your iPhone.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                }

                Spacer()

                VStack(spacing: 12) {
                    // Progress dots
                    HStack(spacing: 6) {
                        ForEach(0..<3) { i in
                            Capsule()
                                .fill(i == 0 ? Theme.accent : Theme.surface)
                                .frame(width: i == 0 ? 20 : 6, height: 6)
                        }
                    }
                    .padding(.bottom, 8)

                    Button {
                        viewModel.advance()
                    } label: {
                        Text("Get Started")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
        }
        .fullScreenCover(isPresented: .constant(viewModel.currentPage == 1)) {
            OnboardingProfileView(viewModel: viewModel)
        }
    }
}
