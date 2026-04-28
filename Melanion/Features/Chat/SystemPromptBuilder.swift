import Foundation

enum SystemPromptBuilder {

    static func build(profile: UserProfile) -> String {
        var parts: [String] = []

        parts.append("""
            You are Melanion, a personal running coach and analyst. \
            You have access to the user's complete running history and health data. \
            Provide clear, specific, data-driven coaching insights.
            """)

        parts.append(profileSection(profile))

        let biomechanics = BundledContext.biomechanicsReference
        if !biomechanics.isEmpty {
            parts.append("## Running Biomechanics Reference\n\(biomechanics)")
        }

        return parts.joined(separator: "\n\n")
    }

    // MARK: - Format hints (injected per-turn by ResponderPipeline, not into session)

    static func formatHint(for format: ResponseFormat) -> String {
        switch format {
        case .stat:
            return "Give a direct single-stat answer with brief context. Two sentences maximum."
        case .rankedList:
            return "Present as a clean numbered list. One line of context per item."
        case .trend:
            return "Describe the trend: direction, magnitude, and what it means for training."
        case .detail:
            return "Give a structured breakdown covering each metric in the data provided."
        }
    }

    // MARK: - Private

    private static func profileSection(_ profile: UserProfile) -> String {
        var lines = ["## Your Athlete"]

        if !profile.name.isEmpty {
            lines.append("Name: \(profile.name)")
        }
        lines.append("Goal: \(profile.goal.rawValue)")
        lines.append("Experience: \(profile.experienceLevel.rawValue)")

        if !profile.targetRace.isEmpty {
            lines.append("Target: \(profile.targetRace)")
        }
        lines.append("Preferred units: \(profile.preferredUnits.rawValue)")

        if let rhr = profile.restingHeartRate {
            lines.append("Resting HR: \(rhr) bpm")
        }
        if let mhr = profile.maxHeartRate {
            lines.append("Max HR: \(mhr) bpm")
        }
        if !profile.injuryNotes.isEmpty {
            lines.append("Injury notes: \(profile.injuryNotes)")
        }

        return lines.joined(separator: "\n")
    }
}
