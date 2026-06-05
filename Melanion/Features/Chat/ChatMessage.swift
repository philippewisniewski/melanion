import Foundation

struct ChatMessage: Identifiable {
    enum Role: Sendable { case user, assistant, error }

    let id: UUID
    let role: Role
    var content: String

    init(role: Role, content: String, id: UUID = UUID()) {
        self.id = id
        self.role = role
        self.content = content
    }
}
