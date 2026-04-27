import Foundation

struct ChatMessage: Identifiable, Sendable {
    enum Role: Sendable { case user, assistant, error }

    let id: UUID = UUID()
    let role: Role
    var content: String
    var responseFormat: ResponseFormat? = nil
}

struct ConversationTurn: Sendable {
    let question: String
    let answer: String
}
