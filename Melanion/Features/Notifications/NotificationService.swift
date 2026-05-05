import Foundation
import UserNotifications

// MARK: - NotificationPayload

struct NotificationPayload: Sendable {
    enum Category: Sendable {
        case runComplete
        case personalBest
        case weeklyTrend
        case recoveryNudge
        case streakMilestone
    }

    enum FireTime: Sendable {
        case seconds(Double)
        case calendar(DateComponents)
    }

    let identifier: String
    let title: String
    let body: String
    let category: Category
    let fireAt: FireTime

    init(id: String, title: String, body: String, category: Category, delay: Double = 3) {
        identifier = id
        self.title = title
        self.body = body
        self.category = category
        fireAt = .seconds(delay)
    }

    init(id: String, title: String, body: String, category: Category, components: DateComponents) {
        identifier = id
        self.title = title
        self.body = body
        self.category = category
        fireAt = .calendar(components)
    }
}

// MARK: - NotificationService

final class NotificationService: NSObject, @unchecked Sendable {
    static let shared = NotificationService()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    // Request authorisation only when at least one category is enabled and status is undetermined.
    func requestPermissionIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let current = await center.notificationSettings()
        guard current.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func schedule(_ payload: NotificationPayload) {
        let content = UNMutableNotificationContent()
        content.title = payload.title
        content.body = payload.body
        content.sound = .default

        let trigger: UNNotificationTrigger
        switch payload.fireAt {
        case .seconds(let interval):
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, interval), repeats: false)
        case .calendar(let components):
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        }

        let request = UNNotificationRequest(identifier: payload.identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: UNUserNotificationCenterDelegate {
    // Suppress all notifications while the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([])
    }
}
