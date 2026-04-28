import Foundation
import FoundationModels

// MARK: - @Generable types

@Generable
enum QueryName: String, Codable, CaseIterable {
    case recentRuns         = "recent_runs"
    case personalBest       = "personal_best"
    case distanceBest       = "distance_best"
    case distanceTopN       = "distance_top_n"
    case overallAverages    = "overall_averages"
    case paceThreshold      = "pace_threshold"
    case hrThreshold        = "hr_threshold"
    case pacingPattern      = "pacing_pattern"
    case kmSplitAnalysis    = "km_split_analysis"
    case durationStats      = "duration_stats"
    case trainingVolume     = "training_volume"
    case runFrequency       = "run_frequency"
    case monthlyRuns        = "monthly_runs"
    case runningStreak      = "running_streak"
    case calorieStats       = "calorie_stats"
    case timeOfDay          = "time_of_day"
    case seasonalComparison = "seasonal_comparison"
    case vo2MaxTrend        = "vo2_max_trend"
    case hilliestRuns       = "hilliest_runs"
    case elevationVsPace    = "elevation_vs_pace"
    case recoveryAnalysis   = "recovery_analysis"
    case restingHR          = "resting_hr"
    case hrRange            = "hr_range"
    case hrRecoveryStats    = "hr_recovery_stats"
    case sleepVsPace        = "sleep_vs_pace"
}

extension QueryName {
    // rawValue is already the snake_case registry name
    var registryName: String { rawValue }
}

@Generable
struct QueryRouting {
    @Guide(description: "Select the query that best matches the user's question.")
    var query: QueryName

    @Guide(description: "Parameters required by the selected query. Use an empty dictionary if none are needed.")
    var params: [String: String]
}

// MARK: - Error

enum ClassifierError: Error, LocalizedError {
    case noMatchFound(String)
    case sessionError(Error)

    var errorDescription: String? {
        switch self {
        case .noMatchFound(let name): return "No query found for '\(name)'"
        case .sessionError(let e):   return "Classifier session error: \(e.localizedDescription)"
        }
    }
}

// MARK: - Pipeline

struct ClassifierPipeline {

    func classify(
        question: String,
        using service: LanguageModelService
    ) async throws -> (any QueryDefinition, [String: String]) {
        let session = service.classifierSession()
        let prompt = buildPrompt(question: question)

        do {
            let response = try await session.respond(
                to: prompt,
                generating: QueryRouting.self,
                options: GenerationOptions(sampling: .greedy)
            )
            let routing = response.content
            guard let definition = QueryRegistry.find(named: routing.query.registryName) else {
                throw ClassifierError.noMatchFound(routing.query.registryName)
            }
            return (definition, routing.params)
        } catch let error as ClassifierError {
            throw error
        } catch {
            throw ClassifierError.sessionError(error)
        }
    }

    // MARK: - Prompt construction

    private func buildPrompt(question: String) -> String {
        let queryList = QueryRegistry.all
            .map { "- \($0.name): \($0.description)" }
            .joined(separator: "\n")

        return """
            You are a query router for a personal running analytics app.
            Given the user's question, select the most appropriate query and extract any required parameters.

            Available queries:
            \(queryList)

            Select the single best matching query. Extract only parameters explicitly stated or clearly implied by the question.

            User question: \(question)
            """
    }
}
