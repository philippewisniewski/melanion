import SwiftUI

@main
struct MelanionApp: App {
    @State private var intelligenceGate = IntelligenceGate()
    @State private var languageModelService = LanguageModelService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(intelligenceGate)
                .environment(languageModelService)
        }
    }
}
