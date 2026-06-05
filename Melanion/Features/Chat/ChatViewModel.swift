import Foundation
import FoundationModels
import Observation

@Observable
@MainActor
final class ChatViewModel {

    var messages: [ChatMessage] = []
    var inputText: String = ""
    var isLoading: Bool = false
    var statusLabel: String = ""

    private let retriever = DataRetriever()
    private var lastQuestion: String = ""

    // MARK: - Send

    func send(using service: LanguageModelService) async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading else { return }
        inputText = ""
        lastQuestion = text
        await run(question: text, using: service)
    }

    func retry(using service: LanguageModelService) async {
        guard !lastQuestion.isEmpty, !isLoading else { return }
        if messages.last?.role == .error { messages.removeLast() }
        await run(question: lastQuestion, using: service)
    }

    // MARK: - Core pipeline

    private func run(question: String, using service: LanguageModelService) async {
        messages.append(ChatMessage(role: .user, content: question))
        isLoading = true
        statusLabel = "Loading data…"

        // 1. Classify question and fetch only relevant data + pre-computed answers
        let (data, precomputed) = await retriever.retrieve(for: question)

        // 2. Fresh session per question (no prior context carried over).
        statusLabel = "Thinking…"
        service.freshSession()

        // 3. Augment prompt with data subset and pre-computed values
        let augmentedPrompt = """
            Running data:
            \(data)

            \(precomputed)

            Question: \(question)
            """

        print("---MELANION PROMPT---")
        print(augmentedPrompt)
        print("---END MELANION PROMPT---")

        // 4. Stream response
        let messageId = UUID()
        messages.append(ChatMessage(role: .assistant, content: "", id: messageId))

        do {
            let stream = service.session.streamResponse(to: augmentedPrompt)
            for try await snapshot in stream {
                statusLabel = ""
                if let idx = messages.firstIndex(where: { $0.id == messageId }) {
                    messages[idx].content = snapshot.content
                }
            }

            if let idx = messages.firstIndex(where: { $0.id == messageId }),
               messages[idx].content.isEmpty {
                messages.remove(at: idx)
                appendError("I couldn't generate a response.")
            }

        } catch {
            print("Melanion stream error: \(error)")
            if let idx = messages.firstIndex(where: { $0.id == messageId }) {
                messages.remove(at: idx)
            }
            appendError("Something went wrong — try rephrasing your question.")
        }

        isLoading = false
        statusLabel = ""
    }

    // MARK: - Welcome data

    func fetchWelcome() async -> WelcomeData? {
        guard let workouts = try? await HealthKitWorkoutFetcher().fetchRunningWorkouts(),
              let last = workouts.first else {
            return nil
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "d MMM yyyy"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        let streak = Self.computeStreak(from: workouts)

        return WelcomeData(
            lastRunDate: dateFormatter.string(from: last.startedAt),
            lastRunDistanceKm: last.distanceKm,
            lastRunPaceSeconds: last.paceSeconds,
            currentStreak: streak
        )
    }

    private nonisolated static func computeStreak(from workouts: [RunWorkout]) -> Int {
        let cal = Calendar.current
        let runDays = Set(workouts.map { cal.startOfDay(for: $0.startedAt) }).sorted(by: >)
        guard let latest = runDays.first else { return 0 }

        var streak = 0
        var expected = latest
        for day in runDays {
            let diff = cal.dateComponents([.day], from: day, to: expected).day ?? 999
            if diff <= 1 { streak += 1; expected = day } else { break }
        }
        return streak
    }

    // MARK: - Helpers

    private func appendError(_ message: String) {
        messages.append(ChatMessage(role: .error, content: message))
    }
}

struct WelcomeData: Sendable {
    let lastRunDate: String
    let lastRunDistanceKm: Double
    let lastRunPaceSeconds: Int
    let currentStreak: Int
}
