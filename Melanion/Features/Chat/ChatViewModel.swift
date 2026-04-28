import Foundation
import GRDB
import FoundationModels
import Observation

@Observable
@MainActor
final class ChatViewModel {

    var messages: [ChatMessage] = []
    var inputText: String = ""
    var isLoading: Bool = false
    var statusLabel: String = ""
    var canRetry: Bool = false

    private var lastQuestion: String = ""
    private let classifier = ClassifierPipeline()
    private let responder = ResponderPipeline()

    // MARK: - Send

    func send(using service: LanguageModelService) async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading else { return }
        inputText = ""
        canRetry = false
        lastQuestion = text
        await run(question: text, using: service)
    }

    func retry(using service: LanguageModelService) async {
        guard !lastQuestion.isEmpty, !isLoading else { return }
        // Remove the last error bubble before retrying
        if messages.last?.role == .error { messages.removeLast() }
        await run(question: lastQuestion, using: service)
    }

    // MARK: - Core pipeline

    private func run(question: String, using service: LanguageModelService) async {
        messages.append(ChatMessage(role: .user, content: question))
        isLoading = true
        statusLabel = "Thinking…"

        do {
            // Step 1 — Classify
            let (definition, params) = try await classifier.classify(question: question, using: service)

            // Step 2 — Execute SQL query
            statusLabel = "Querying your data…"
            let rows: [[String: Any?]]
            do {
                rows = try await DatabaseManager.shared.db.read { db in
                    try definition.execute(db: db, params: params)
                }
            } catch {
                print("[ChatViewModel] SQL error: \(error)")
                appendError("Something went wrong querying your data.")
                reset()
                return
            }

            // Step 3 — Format Markdown table
            let markdownTable = MarkdownTableFormatter.format(rows)

            // Step 4 — Stream response
            statusLabel = "Generating response…"
            var assistantMessage = ChatMessage(role: .assistant, content: "")
            messages.append(assistantMessage)
            let messageId = assistantMessage.id

            let stream = responder.respond(
                question: question,
                markdownTable: markdownTable,
                format: definition.format,
                using: service
            )

            for await partial in stream {
                if let idx = messages.firstIndex(where: { $0.id == messageId }) {
                    messages[idx].content = partial   // replace — each partial is a full snapshot
                }
            }

            // Step 5 — Attach card data (or show error if stream produced nothing)
            if let idx = messages.firstIndex(where: { $0.id == messageId }) {
                if messages[idx].content.isEmpty {
                    messages.remove(at: idx)
                    appendError("I couldn't generate a response.")
                    canRetry = true
                } else {
                    messages[idx].responseFormat = definition.format
                    messages[idx].cardRows = rows
                }
            }

        } catch is ClassifierError {
            appendError("I couldn't understand that — try rephrasing your question.")
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            appendError("Your data was too large to process. Try a more specific question.")
        } catch {
            appendError("I couldn't understand that — try rephrasing your question.")
        }

        reset()
    }

    // MARK: - Welcome data

    func fetchWelcome() async -> WelcomeData? {
        try? await DatabaseManager.shared.db.read { db in
            guard let run = try RunRecord
                .order(Column("started_at").desc)
                .fetchOne(db)
            else { return nil }

            let streak = try Self.computeStreak(db: db)
            return WelcomeData(
                lastRunDate: run.date,
                lastRunDistanceKm: run.distanceKm,
                lastRunPaceSeconds: run.paceSeconds,
                currentStreak: streak
            )
        }
    }

    private nonisolated static func computeStreak(db: Database) throws -> Int {
        let dates = try String.fetchAll(db, sql: "SELECT DISTINCT date FROM runs ORDER BY date DESC")
        guard !dates.isEmpty else { return 0 }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        var streak = 0
        var expected = Calendar.current.startOfDay(for: Date())
        for dateStr in dates {
            guard let date = formatter.date(from: dateStr) else { continue }
            let day = Calendar.current.startOfDay(for: date)
            let diff = Calendar.current.dateComponents([.day], from: day, to: expected).day ?? 999
            if diff <= 1 { streak += 1; expected = day } else { break }
        }
        return streak
    }

    // MARK: - Helpers

    private func appendError(_ message: String) {
        messages.append(ChatMessage(role: .error, content: message))
    }

    private func reset() {
        isLoading = false
        statusLabel = ""
    }
}

struct WelcomeData: Sendable {
    let lastRunDate: String
    let lastRunDistanceKm: Double
    let lastRunPaceSeconds: Int
    let currentStreak: Int
}
