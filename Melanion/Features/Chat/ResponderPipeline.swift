import Foundation
import FoundationModels

struct ResponderPipeline {

    func respond(
        question: String,
        markdownTable: String,
        format: ResponseFormat,
        using service: LanguageModelService
    ) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task { @MainActor in
                do {
                    let userTurn = buildUserTurn(
                        question: question,
                        markdownTable: markdownTable,
                        format: format
                    )
                    let stream = service.responderSession.streamResponse(to: userTurn)
                    for try await partial in stream {
                        continuation.yield(partial)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish()
                }
            }
        }
    }

    // MARK: - User turn assembly

    private func buildUserTurn(
        question: String,
        markdownTable: String,
        format: ResponseFormat
    ) -> String {
        let hint = SystemPromptBuilder.formatHint(for: format)
        return """
            \(question)

            Here is your data:
            \(markdownTable)

            Response format instruction: \(hint)
            """
    }
}
