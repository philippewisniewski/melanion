import SwiftUI

@main
struct MelanionApp: App {
    @State private var intelligenceGate = IntelligenceGate()
    @State private var languageModelService = LanguageModelService()

    init() {
        // Initialise the notification service early so its UNUserNotificationCenterDelegate
        // is registered before the first notification can arrive.
        _ = NotificationService.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(intelligenceGate)
                .environment(languageModelService)
        }
    }
}
