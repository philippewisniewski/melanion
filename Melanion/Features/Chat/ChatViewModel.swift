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

        let intent = retriever.classify(question)
        let (data, precomputed) = await retriever.retrieve(for: question)

        statusLabel = "Thinking…"
        service.freshSession()

        let augmentedPrompt = """
            \(data)

            \(precomputed)

            Question: \(question)
            """

        print("---MELANION PROMPT---")
        print(augmentedPrompt)
        print("---END MELANION PROMPT---")

        let messageId = UUID()
        messages.append(ChatMessage(role: .assistant, content: "", id: messageId))

        let succeeded = await streamByIntent(intent, prompt: augmentedPrompt, using: service, messageId: messageId)

        if !succeeded {
            if let idx = messages.firstIndex(where: { $0.id == messageId }) {
                messages.remove(at: idx)
            }
            await fallbackStream(prompt: augmentedPrompt, messageId: messageId, using: service)
        }

        if let idx = messages.firstIndex(where: { $0.id == messageId }),
           messages[idx].content.isEmpty {
            messages.remove(at: idx)
            appendError("I couldn't generate a response.")
        }

        isLoading = false
        statusLabel = ""
    }

    // MARK: - Per-intent streaming

    private func streamByIntent(_ intent: DataRetriever.Intent, prompt: String, using service: LanguageModelService, messageId: UUID) async -> Bool {
        let options = GenerationOptions(sampling: .greedy, temperature: nil)

        switch intent {
        case .lastRun, .longestRun, .fastestRun, .slowestRun:
            return await streamGenerable(prompt: prompt, type: SingleRunResponse.self, format: formatSingleRun, service: service, messageId: messageId, options: options)
        case .lastFew, .topFew, .calories, .elevation, .heartRate, .cadence, .paceFilter:
            return await streamGenerable(prompt: prompt, type: RunListResponse.self, format: formatRunList, service: service, messageId: messageId, options: options)
        case .trends, .weeklyMonthly:
            return await streamGenerable(prompt: prompt, type: TrendResponse.self, format: formatTrend, service: service, messageId: messageId, options: options)
        case .recovery:
            return await streamGenerable(prompt: prompt, type: RecoveryResponse.self, format: formatRecovery, service: service, messageId: messageId, options: options)
        case .general, .total, .streaks, .averagePace, .averageDistance, .routes:
            return await streamGenerable(prompt: prompt, type: GeneralResponse.self, format: formatGeneral, service: service, messageId: messageId, options: options)
        }
    }

    private func streamGenerable<Content: Generable>(
        prompt: String,
        type: Content.Type,
        format: @escaping (Content.PartiallyGenerated) -> String,
        service: LanguageModelService,
        messageId: UUID,
        options: GenerationOptions
    ) async -> Bool {
        do {
            let stream = service.session.streamResponse(
                to: prompt,
                generating: type,
                includeSchemaInPrompt: true,
                options: options
            )

            for try await snapshot in stream {
                statusLabel = ""
                let formatted = format(snapshot.content)
                if let idx = messages.firstIndex(where: { $0.id == messageId }) {
                    messages[idx].content = formatted
                }
            }
            return true
        } catch {
            print("Melanion generable error: \(error)")
            return false
        }
    }

    // MARK: - Fallback

    private func fallbackStream(prompt: String, messageId: UUID, using service: LanguageModelService) async {
        messages.append(ChatMessage(role: .assistant, content: "", id: messageId))
        let options = GenerationOptions(sampling: .greedy, temperature: nil)
        do {
            let stream = service.session.streamResponse(to: prompt, options: options)
            for try await snapshot in stream {
                statusLabel = ""
                if let idx = messages.firstIndex(where: { $0.id == messageId }) {
                    messages[idx].content = snapshot.content
                }
            }
        } catch {
            print("Melanion fallback error: \(error)")
        }
    }

    // MARK: - Formatting (PartiallyGenerated → String)

    private func formatSingleRun(_ r: SingleRunResponse.PartiallyGenerated) -> String {
        var parts: [String] = []
        if let d = r.distanceKm {
            let label = r.date.map { "Your run on \($0)" } ?? "Your run"
            parts.append("\(label) covered \(String(format: "%.1f", d)) km.")
        } else if let date = r.date {
            parts.append("Your run on \(date) was recorded.")
        }
        if let dur = r.durationSeconds {
            parts.append("Duration was \(formatDuration(dur)).")
        }
        if let p = r.paceSeconds {
            parts.append("Pace was \(formatPace(p)).")
        }
        if let hr = r.heartRateBpm { parts.append("Average heart rate was \(hr) bpm.") }
        if let cal = r.caloriesKcal { parts.append("You burned \(cal) calories.") }
        if let elev = r.elevationMetres { parts.append("The route climbed \(elev) metres.") }
        if let cad = r.cadenceSpm { parts.append("Average cadence was \(cad) steps per minute.") }
        if let splits = r.splitsPerKm, !splits.isEmpty {
            parts.append("Splits per km: " + splits.joined(separator: ", ") + ".")
        }
        guard !parts.isEmpty else { return "I couldn't find enough information about that run." }
        return parts.joined(separator: "\n")
    }

    private func formatRunList(_ list: RunListResponse.PartiallyGenerated) -> String {
        var parts: [String] = []
        if let title = list.title {
            parts.append("\(title):")
        }
        if let runs = list.runs {
            for run in runs {
                let date = run.date ?? "Unknown date"
                let dist = run.distanceKm.map { String(format: "%.1f", $0) } ?? "unknown distance"
                let pace = run.paceSeconds.map { formatPace($0) }
                var line = "\(date) — \(dist) km"
                if let p = pace { line += " at \(p)" }
                if let label = run.label, !label.isEmpty { line += ", \(label)" }
                line += "."
                parts.append(line)
            }
        }
        guard !parts.isEmpty else { return "" }
        return parts.joined(separator: "\n")
    }

    private func formatTrend(_ t: TrendResponse.PartiallyGenerated) -> String {
        var parts: [String] = []
        if let s = t.summary { parts.append(s) }
        if let b = t.beforeAfter { parts.append(b) }
        guard !parts.isEmpty else { return "I couldn't find enough data to show a trend." }
        return parts.joined(separator: "\n")
    }

    private func formatRecovery(_ r: RecoveryResponse.PartiallyGenerated) -> String {
        var parts: [String] = []
        if let a = r.assessment { parts.append(a) }
        if let hrv = r.hrvMs { parts.append("HRV was \(hrv) ms.") }
        if let rhr = r.restingHeartRateBpm { parts.append("Resting heart rate was \(rhr) bpm.") }
        if let hrr = r.heartRateRecoveryBpm { parts.append("Heart rate recovery was \(hrr) bpm.") }
        if let sleep = r.sleepHours { parts.append("Sleep was \(String(format: "%.1f", sleep)) hours.") }
        if let spo2 = r.bloodOxygenPct { parts.append("Blood oxygen was \(String(format: "%.1f", spo2))%.") }
        guard !parts.isEmpty else { return "There isn't enough recovery data for a meaningful answer yet. Keep running and checking back as more data accumulates." }
        return parts.joined(separator: "\n")
    }

    private func formatGeneral(_ g: GeneralResponse.PartiallyGenerated) -> String {
        var parts: [String] = []
        if let a = g.answer { parts.append(a) }
        if let details = g.details {
            parts.append(contentsOf: details)
        }
        guard !parts.isEmpty else { return "I couldn't find enough information to answer that." }
        return parts.joined(separator: "\n")
    }

    // MARK: - Display Formatters

    private func formatPace(_ totalSeconds: Int) -> String {
        let capped = min(totalSeconds, 1800)
        let minutes = capped / 60
        let seconds = capped % 60
        return String(format: "%d:%02d per km", minutes, seconds)
    }

    private func formatDuration(_ totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            if minutes > 0 { return "\(hours) hours \(minutes) minutes" }
            return "\(hours) hours"
        }
        if minutes > 0 {
            if secs > 0 { return "\(minutes) minutes \(secs) seconds" }
            return "\(minutes) minutes"
        }
        return "\(secs) seconds"
    }

    // MARK: - Helpers

    private func appendError(_ message: String) {
        messages.append(ChatMessage(role: .error, content: message))
    }
}
