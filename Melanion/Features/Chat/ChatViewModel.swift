import SwiftUI
import GRDB
import Observation

@Observable
@MainActor
final class ChatViewModel {

    var messages: [ChatMessage] = []
    var inputText: String = ""
    var isLoading: Bool = false

    // Conversation history — passed to LLM pipeline in Stage 4
    private(set) var history: [ConversationTurn] = []
    private let maxHistory = 20

    // MARK: - Send

    func send() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading else { return }
        inputText = ""

        messages.append(ChatMessage(role: .user, content: text))
        isLoading = true

        // Stage 4 will replace this stub with the real CoreML pipeline
        do {
            let response = try await stubbedResponse(for: text)
            messages.append(ChatMessage(role: .assistant, content: response.answer, responseFormat: response.format))
            trimHistory()
            history.append(ConversationTurn(question: text, answer: response.answer))
        } catch {
            messages.append(ChatMessage(role: .error, content: error.localizedDescription))
        }
        isLoading = false
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
            if diff <= 1 {
                streak += 1
                expected = day
            } else { break }
        }
        return streak
    }

    // MARK: - History management

    private func trimHistory() {
        if history.count >= maxHistory {
            history.removeFirst()
        }
    }

    // MARK: - Stub (replaced in Stage 4)

    private struct StubResponse {
        let answer: String
        let format: ResponseFormat
    }

    private func stubbedResponse(for question: String) async throws -> StubResponse {
        try await Task.sleep(for: .seconds(1.2))
        return StubResponse(
            answer: "I can see you asked: \"\(question)\". The AI pipeline will be connected in Stage 4 — your data layer is fully wired and ready.",
            format: .stat
        )
    }
}

struct WelcomeData: Sendable {
    let lastRunDate: String
    let lastRunDistanceKm: Double
    let lastRunPaceSeconds: Int
    let currentStreak: Int
}
