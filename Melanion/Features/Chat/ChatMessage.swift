import Foundation

struct ChatMessage: Identifiable, @unchecked Sendable {
    enum Role: Sendable { case user, assistant, error }

    let id: UUID = UUID()
    let role: Role
    var content: String
    var responseFormat: ResponseFormat? = nil
    var cardRows: [[String: Any?]]? = nil
}
