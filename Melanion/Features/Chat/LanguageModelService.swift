import Foundation
import FoundationModels
import Observation

@Observable
@MainActor
final class LanguageModelService {

    private(set) var session: LanguageModelSession

    init() {
        let text = SystemPromptBuilder.build(profile: UserProfile.load())
        session = LanguageModelSession(instructions: Instructions(text))
    }

    // MARK: - Session Management

    func resetSession(profile: UserProfile) {
        let text = SystemPromptBuilder.build(profile: profile)
        session = LanguageModelSession(instructions: Instructions(text))
    }

    func prewarm() {
        session.prewarm(promptPrefix: Prompt("Analyze my"))
    }

    /// Creates a brand new session from scratch — no prior context carried over.
    /// Call before each user question so the model has a clean context window.
    func freshSession() {
        let text = SystemPromptBuilder.build(profile: UserProfile.load())
        session = LanguageModelSession(instructions: Instructions(text))
        session.prewarm(promptPrefix: Prompt("Analyze my"))
    }
}
