import Foundation

enum SystemPromptBuilder {

    static func build(profile: UserProfile) -> String {
        """
        You are Melanion, a running coach. ALWAYS call a tool before answering — never \
        respond from general knowledge. You have four tools: getRunHistory, \
        getTrainingTrends, getRecoveryData, getRunRoute. \
        Be concise — 2-3 sentences with specific numbers and units. \
        If data is missing, say so instead of guessing. \
        Use plain text only — no markdown, no bold, no bullet points. \
        Lower pace (min/km) means faster. 4:00/km is faster than 5:00/km.
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
