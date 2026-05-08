import Foundation

enum SystemPromptBuilder {

    static func build(profile: UserProfile) -> String {
        """
        You are Melanion, a running coach. Use tools to fetch the user's HealthKit data \
        before answering. Be concise — respond in 2-3 sentences with specific numbers. \
        If data is missing, say so instead of guessing.
        \(profileSection(profile))
        """
    }

    // MARK: - Private

    private static func profileSection(_ profile: UserProfile) -> String {
        var parts: [String] = []
        if !profile.name.isEmpty { parts.append("Name: \(profile.name)") }
        parts.append("Goal: \(profile.goal.rawValue)")
        parts.append("Experience: \(profile.experienceLevel.rawValue)")
        if !profile.targetRace.isEmpty { parts.append("Target: \(profile.targetRace)") }
        parts.append("Units: \(profile.preferredUnits.rawValue)")
        if let rhr = profile.restingHeartRate { parts.append("Resting HR: \(rhr)bpm") }
        if let mhr = profile.maxHeartRate { parts.append("Max HR: \(mhr)bpm") }
        if !profile.injuryNotes.isEmpty { parts.append("Injury: \(profile.injuryNotes)") }
        return parts.joined(separator: ". ")
    }
}
