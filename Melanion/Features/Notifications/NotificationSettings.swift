import Foundation

struct NotificationSettings: Codable, Sendable {
    var runComplete: Bool = true
    var personalBest: Bool = true
    var weeklyTrend: Bool = true
    var recoveryNudge: Bool = false
    var streakMilestone: Bool = true

    private static let key = "notificationSettings"

    static func load() -> NotificationSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(NotificationSettings.self, from: data)
        else { return NotificationSettings() }
        return settings
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: NotificationSettings.key)
    }
}
