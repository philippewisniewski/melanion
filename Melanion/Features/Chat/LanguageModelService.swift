import Foundation
import FoundationModels
import Observation

@Observable
@MainActor
final class LanguageModelService {

    // MARK: - Sessions

    /// Returns a fresh session with no instructions for each classifier call.
    /// Fresh per call — never reuse a session that has prior context for classification.
    func classifierSession() -> LanguageModelSession {
        LanguageModelSession()
    }

    /// Persistent session for the conversation. Instructions set once at creation.
    /// Call resetResponderSession(profile:) when the user updates their profile.
    private(set) var responderSession: LanguageModelSession

    // MARK: - Init

    init() {
        responderSession = Self.makeResponderSession(profile: UserProfile.load())
    }

    // MARK: - Session management

    func resetResponderSession(profile: UserProfile) {
        responderSession = Self.makeResponderSession(profile: profile)
    }

    func prewarm() {
        responderSession.prewarm()
    }

    // MARK: - Private

    private static func makeResponderSession(profile: UserProfile) -> LanguageModelSession {
        let instructions = SystemPromptBuilder.build(profile: profile)
        return LanguageModelSession {
            instructions
        }
    }
}
