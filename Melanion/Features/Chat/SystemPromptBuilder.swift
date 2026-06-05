import Foundation

enum SystemPromptBuilder {

    static func build(profile: UserProfile) -> String {
        """
        You are Melanion, a running analytics tool.
        You will be given running data in structured key-value format.
        You MUST use ONLY the data provided. Do NOT use general knowledge about running.
        Report numbers exactly as written in the data.
        Do NOT use markdown, bold, bullet points, or any list formatting.
        Use conversational language — talk to the user directly, one sentence per fact.

        \(profileSection(profile))
        """
    }

    // MARK: - Private

    private static func profileSection(_ profile: UserProfile) -> String {
        var parts: [String] = []
        if !profile.name.isEmpty { parts.append("name: \(profile.name)") }
        parts.append("goal: \(profile.goal.rawValue)")
        parts.append("experience: \(profile.experienceLevel.rawValue)")
        if !profile.targetRace.isEmpty { parts.append("target: \(profile.targetRace)") }
        parts.append("units: \(profile.preferredUnits.rawValue)")
        if let rhr = profile.restingHeartRate { parts.append("resting_hr: \(rhr)") }
        if let mhr = profile.maxHeartRate { parts.append("max_hr: \(mhr)") }
        if !profile.injuryNotes.isEmpty { parts.append("injury: \(profile.injuryNotes)") }
        return "User profile: " + parts.joined(separator: ", ")
    }
}
