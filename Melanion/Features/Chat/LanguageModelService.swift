import Foundation
import FoundationModels
import Observation

@Observable
@MainActor
final class LanguageModelService {

    private(set) var session: LanguageModelSession

    let tools: [any Tool] = [
        RunHistoryTool(),
        TrainingTrendsTool(),
        RecoveryTool(),
        RouteTool()
    ]

    init() {
        let instructions = SystemPromptBuilder.build(profile: UserProfile.load())
        session = LanguageModelSession(tools: [
            RunHistoryTool(),
            TrainingTrendsTool(),
            RecoveryTool(),
            RouteTool()
        ], instructions: instructions)
    }

    func resetSession(profile: UserProfile) {
        let instructions = SystemPromptBuilder.build(profile: profile)
        session = LanguageModelSession(tools: tools, instructions: instructions)
    }

    func prewarm() {
        session.prewarm(promptPrefix: "Analyze my")
    }
}
