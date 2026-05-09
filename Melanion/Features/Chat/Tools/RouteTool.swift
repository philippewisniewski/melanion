import Foundation
import FoundationModels
import HealthKit

struct RouteTool: Tool {
    let name = "getRunRoute"
    let description = "Fetch route splits and elevation for a run"

    @Generable
    struct Arguments {
        @Guide(description: "ISO date string or 'latest'")
        var runDate: String
    }

    func call(arguments: Arguments) async throws -> String {
        let rawWorkouts = try await fetchRawWorkouts()
        let sorted = rawWorkouts.sorted { $0.startDate > $1.startDate }
        guard let mostRecent = sorted.first else {
            return "No running workouts found."
        }

        let targetWorkout: HKWorkout
        if arguments.runDate.lowercased() == "latest" {
            targetWorkout = mostRecent
        } else {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            if let parsed = formatter.date(from: arguments.runDate),
               let match = rawWorkouts.first(where: {
                   Calendar.current.isDate($0.startDate, inSameDayAs: parsed)
               }) {
                targetWorkout = match
            } else {
                targetWorkout = mostRecent
            }
        }

        let routes = await HealthKitRouteFetcher().fetchRoutes(for: [targetWorkout])
        guard let route = routes.first else {
            return "No route data available for this run."
        }

        return formatRoute(route)
    }

    // MARK: - Raw workout fetch

    private func fetchRawWorkouts() async throws -> [HKWorkout] {
        let store = HealthKitPermissionManager.shared.store
        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForWorkouts(with: .running)
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error))
                    return
                }
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(query)
        }
    }

    // MARK: - Formatting

    private func formatRoute(_ route: RouteData) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "d MMM yyyy"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        var lines: [String] = [
            "Route for run on \(dateFormatter.string(from: route.runStartedAt)):",
            "Total elevation gain: \(String(format: "%.0fm", route.elevationGainMetres))",
            "\(route.kmSplits.count) km splits:"
        ]

        for split in route.kmSplits {
            let pace = formatPace(split.splitSeconds)
            let elev = String(format: "+%.0fm/-%.0fm", split.elevationGainM, split.elevationLossM)
            lines.append("- km \(split.km): \(pace), \(elev)")
        }

        return lines.joined(separator: "\n")
    }

    private func formatPace(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d/km", minutes, seconds)
    }
}
