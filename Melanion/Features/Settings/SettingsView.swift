import SwiftUI

struct SettingsView: View {
    @State private var profile = UserProfile.load()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 32) {

                    SettingsSection(title: "Profile") {
                        SettingsTextField(label: "Name", placeholder: "Your name", text: $profile.name)
                        SettingsPicker(label: "Goal", selection: $profile.goal)
                        SettingsPicker(label: "Experience", selection: $profile.experienceLevel)
                        SettingsTextField(label: "Target Race", placeholder: "e.g. Paris Marathon 2027", text: $profile.targetRace)
                        SettingsTextField(label: "Injury Notes", placeholder: "Any current injuries", text: $profile.injuryNotes)
                    }

                    SettingsSection(title: "Health Baselines") {
                        SettingsOptionalIntField(label: "Resting Heart Rate", unit: "bpm", value: $profile.restingHeartRate)
                        SettingsOptionalIntField(label: "Max Heart Rate", unit: "bpm", value: $profile.maxHeartRate)
                    }

                    SettingsSection(title: "Preferences") {
                        SettingsPicker(label: "Units", selection: $profile.preferredUnits)
                    }
                }
                .padding(24)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    profile.save()
                    dismiss()
                }
                .foregroundStyle(Theme.accent)
            }
        }
        .onChange(of: profile.goal) { profile.save() }
        .onChange(of: profile.experienceLevel) { profile.save() }
        .onChange(of: profile.preferredUnits) { profile.save() }
    }
}

// MARK: - Section wrapper

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.textSecondary)
                .textCase(.uppercase)
                .tracking(1)
            VStack(spacing: 0) {
                content()
            }
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Row components

private struct SettingsTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                TextField(placeholder, text: $text)
                    .multilineTextAlignment(.trailing)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            Divider().background(Theme.background).padding(.leading, 16)
        }
    }
}

private struct SettingsPicker<T: RawRepresentable & CaseIterable & Hashable & Sendable>: View
where T.RawValue == String, T.AllCases: RandomAccessCollection {
    let label: String
    @Binding var selection: T

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Picker("", selection: $selection) {
                    ForEach(Array(T.allCases), id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .tint(Theme.accent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            Divider().background(Theme.background).padding(.leading, 16)
        }
    }
}

private struct SettingsOptionalIntField: View {
    let label: String
    let unit: String
    @Binding var value: Int?

    @State private var text: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                HStack(spacing: 4) {
                    TextField("—", text: $text)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 60)
                    Text(unit)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            Divider().background(Theme.background).padding(.leading, 16)
        }
        .onAppear {
            if let v = value { text = "\(v)" }
        }
        .onChange(of: text) {
            value = Int(text)
        }
    }
}
