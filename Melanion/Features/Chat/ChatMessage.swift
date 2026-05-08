import Foundation

struct ChatMessage: Identifiable {
    enum Role: Sendable { case user, assistant, error }

    let id: UUID = UUID()
    let role: Role
    var content: String
}
