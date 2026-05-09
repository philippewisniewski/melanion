import Foundation
import FoundationModels
import HealthKit

struct RouteTool: Tool {
    let name = "getRunRoute"
    let description = "Fetch per-km splits, pacing, and elevation profile for a run"

    @Generable
    struct Arguments {
        @Guide(description: "ISO date string or 'latest'")
        var runDate: String
    }

    func call(arguments: Arguments) async throws -> String {
        let pairs = try await HealthKitWorkoutFetcher().fetchRunningWorkoutPairs()
        guard let first = pairs.first else {
            return "No running workouts found."
        }

        let target: (mapped: RunWorkout, raw: HKWorkout)
        if arguments.runDate.lowercased() == "latest" {
            target = first
        } else {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            if let parsed = formatter.date(from: arguments.runDate),
               let match = pairs
                .filter({ Calendar.current.isDate($0.mapped.startedAt, inSameDayAs: parsed) })
                .first {
                target = match
            } else {
                target = first
            }
        }

        let routes = await HealthKitRouteFetcher().fetchRoutes(for: [target.raw])
        guard let route = routes.first else {
            return "No route data available for this run."
        }

        return formatRoute(route)
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
