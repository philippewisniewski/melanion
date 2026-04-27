import SwiftUI

struct OnboardingProfileView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text("About You")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Help Melanion personalise your coaching.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 60)
                .padding(.bottom, 32)

                ScrollView {
                    VStack(spacing: 20) {
                        // Name
                        OnboardingField(label: "Your name", placeholder: "e.g. Phil") {
                            TextField("", text: $viewModel.profile.name)
                                .onboardingTextStyle()
                        }

                        // Running goal
                        OnboardingField(label: "Running goal") {
                            Picker("Goal", selection: $viewModel.profile.goal) {
                                ForEach(UserProfile.RunningGoal.allCases, id: \.self) { goal in
                                    Text(goal.rawValue).tag(goal)
                                }
                            }
                            .pickerStyle(.segmented)
                            .colorScheme(.dark)
                        }

                        // Target race
                        OnboardingField(label: "Target race or distance", placeholder: "e.g. Sub-3hr marathon") {
                            TextField("", text: $viewModel.profile.targetRace)
                                .onboardingTextStyle()
                        }

                        // Experience level
                        OnboardingField(label: "Experience level") {
                            Picker("Level", selection: $viewModel.profile.experienceLevel) {
                                ForEach(UserProfile.ExperienceLevel.allCases, id: \.self) { level in
                                    Text(level.rawValue).tag(level)
                                }
                            }
                            .pickerStyle(.segmented)
                            .colorScheme(.dark)
                        }

                        // Injury notes
                        OnboardingField(label: "Injury history or focus areas", placeholder: "e.g. Left knee, focus on cadence") {
                            TextField("", text: $viewModel.profile.injuryNotes)
                                .onboardingTextStyle()
                        }

                        // Units
                        OnboardingField(label: "Preferred units") {
                            Picker("Units", selection: $viewModel.profile.preferredUnits) {
                                ForEach(UserProfile.UnitPreference.allCases, id: \.self) { unit in
                                    Text(unit.rawValue).tag(unit)
                                }
                            }
                            .pickerStyle(.segmented)
                            .colorScheme(.dark)
                        }

                        // Heart rate zones (optional)
                        HStack(spacing: 12) {
                            OnboardingField(label: "Resting HR (optional)") {
                                TextField("bpm", value: $viewModel.profile.restingHeartRate, format: .number)
                                    .onboardingTextStyle()
                                    .keyboardType(.numberPad)
                            }
                            OnboardingField(label: "Max HR (optional)") {
                                TextField("bpm", value: $viewModel.profile.maxHeartRate, format: .number)
                                    .onboardingTextStyle()
                                    .keyboardType(.numberPad)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 120)
                }

                // Bottom bar
                VStack(spacing: 12) {
                    HStack(spacing: 6) {
                        ForEach(0..<3) { i in
                            Capsule()
                                .fill(i == 1 ? Theme.accent : Theme.surface)
                                .frame(width: i == 1 ? 20 : 6, height: 6)
                        }
                    }

                    Button {
                        viewModel.advance()
                    } label: {
                        Text("Continue")
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
                .background(Theme.background)
            }
        }
        .fullScreenCover(isPresented: .constant(viewModel.currentPage == 2)) {
            OnboardingPermissionsView(viewModel: viewModel)
        }
    }
}

// MARK: - Reusable field wrapper

struct OnboardingField<Content: View>: View {
    let label: String
    var placeholder: String = ""
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(Theme.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)
            content()
        }
    }
}

extension View {
    func onboardingTextStyle() -> some View {
        self
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
