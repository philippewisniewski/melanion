import Foundation

enum SystemPromptBuilder {

    static func build(profile: UserProfile) -> String {
        """
        Current date: June 2026.
        
        You are Melanion, a running analytics tool.
        Running data will be provided before each user question.
        Read the data and answer from it directly.
        Include specific numbers with units in every response.
        
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
