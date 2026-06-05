import FoundationModels

// MARK: - Single Run (lastRun, longestRun, fastestRun, slowestRun)

@Generable(description: "Summary of a single run with all available metrics")
struct SingleRunResponse {
    @Guide(description: "Date of the run, e.g. 22 May 2026")
    var date: String
    @Guide(description: "Distance in kilometres")
    var distanceKm: Double
    @Guide(description: "Pace in seconds per kilometre, e.g. 312")
    var paceSeconds: Int
    @Guide(description: "Duration in seconds")
    var durationSeconds: Int
    @Guide(description: "Average heart rate in bpm, if available")
    var heartRateBpm: Int?
    @Guide(description: "Active calories burned in kcal, if available")
    var caloriesKcal: Int?
    @Guide(description: "Elevation gain in metres, if available")
    var elevationMetres: Int?
    @Guide(description: "Cadence in steps per minute, if available")
    var cadenceSpm: Int?
}

// MARK: - Run List (lastFew, calories, elevation, heartRate, cadence)

@Generable(description: "A ranked list of runs")
struct RunListResponse {
    @Guide(description: "Short title describing the list, e.g. Your Top 5 Longest Runs")
    var title: String
    @Guide(description: "Runs in ranked order with stats")
    var runs: [RunListItem]
}

@Generable
struct RunListItem {
    @Guide(description: "Date of the run, e.g. 22 May 2026")
    var date: String
    @Guide(description: "Distance in kilometres")
    var distanceKm: Double
    @Guide(description: "Pace in seconds per kilometre")
    var paceSeconds: Int
    @Guide(description: "Optional descriptive label highlighting what makes this run notable compared to others")
    var label: String?
}

// MARK: - Trend / Comparison (trends, weeklyMonthly)

@Generable(description: "Trend or comparison over time")
struct TrendResponse {
    @Guide(description: "Step-by-step reasoning comparing the data to reach a conclusion")
    var reasoning: String
    @Guide(description: "One-line summary of the trend")
    var summary: String
    @Guide(description: "Before and after comparison with specific numbers")
    var beforeAfter: String
}

// MARK: - Recovery (recovery)

@Generable(description: "Recovery metrics assessment")
struct RecoveryResponse {
    @Guide(description: "One-line recovery assessment")
    var assessment: String
    @Guide(description: "Heart rate variability in milliseconds, if available")
    var hrvMs: Int?
    @Guide(description: "Resting heart rate in bpm, if available")
    var restingHeartRateBpm: Int?
    @Guide(description: "Heart rate recovery in bpm, if available")
    var heartRateRecoveryBpm: Int?
    @Guide(description: "Sleep duration in hours, if available")
    var sleepHours: Double?
    @Guide(description: "Blood oxygen percentage, if available")
    var bloodOxygenPct: Double?
}

// MARK: - General (general, total, streaks, averagePace, averageDistance, routes)

@Generable(description: "General answer to a running question")
struct GeneralResponse {
    @Guide(description: "Step-by-step reasoning to answer the question")
    var reasoning: String
    @Guide(description: "Direct answer to the question")
    var answer: String
    @Guide(description: "Supporting numbers, one per line")
    var details: [String]
}
