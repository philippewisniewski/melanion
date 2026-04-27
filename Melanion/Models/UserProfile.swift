import Foundation

struct UserProfile: Codable, Sendable {
    var name: String = ""
    var goal: RunningGoal = .generalFitness
    var targetRace: String = ""
    var experienceLevel: ExperienceLevel = .intermediate
    var injuryNotes: String = ""
    var preferredUnits: UnitPreference = .kilometres
    var restingHeartRate: Int? = nil
    var maxHeartRate: Int? = nil

    enum RunningGoal: String, Codable, CaseIterable, Sendable {
        case generalFitness   = "General Fitness"
        case raceTraining     = "Race Training"
        case pbChasing        = "PB Chasing"
        case recoveryFocused  = "Recovery Focused"
    }

    enum ExperienceLevel: String, Codable, CaseIterable, Sendable {
        case beginner     = "Beginner"
        case intermediate = "Intermediate"
        case advanced     = "Advanced"
    }

    enum UnitPreference: String, Codable, CaseIterable, Sendable {
        case kilometres = "km"
        case miles      = "mi"
    }
}

// UserDefaults persistence helpers
extension UserProfile {
    static let userDefaultsKey = "userProfile"

    static func load() -> UserProfile {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let profile = try? JSONDecoder().decode(UserProfile.self, from: data)
        else { return UserProfile() }
        return profile
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: UserProfile.userDefaultsKey)
    }
}
