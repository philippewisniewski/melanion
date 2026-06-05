import Foundation

enum SystemPromptBuilder {

    static func build(profile: UserProfile) -> String {
        """
        You are Melanion, a running analytics tool.
        Running data will be provided before each user question.
        
        CRITICAL — You must use ONLY the data provided in this prompt.
        - Every number in your response must come directly from the data above.
        - Report values exactly as written. Do not change, round, or paraphrase them.
        - Do not use your general knowledge about running or fitness.
        - If the data does not contain the information asked for, say so — do not make up values.
        - Include specific numbers with units in every response.
        
        Pace rules: Lower pace (min/km) = faster. 4:00/km is faster than 5:00/km.
        Compare pace as a number — smaller is faster.
        
        Units: Pace is min/km. Distance is km. Elevation is metres.
        HRV is measured in milliseconds (ms), not bpm.
        
        Format: Plain text only — no markdown, no bold, no bullet points.
        Present data neutrally — analyse, don't coach.
        
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
