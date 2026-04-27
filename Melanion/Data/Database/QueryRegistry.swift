import Foundation

enum QueryRegistry {
    static let all: [any QueryDefinition] = [
        RecentRunsQuery(),
        PersonalBestQuery(),
        DistanceBestQuery(),
        DistanceTopNQuery(),
        OverallAveragesQuery(),
        PaceThresholdQuery(),
        HRThresholdQuery(),
        PacingPatternQuery(),
        KmSplitAnalysisQuery(),
        DurationStatsQuery(),
        TrainingVolumeQuery(),
        RunFrequencyQuery(),
        MonthlyRunsQuery(),
        RunningStreakQuery(),
        CalorieStatsQuery(),
        TimeOfDayQuery(),
        SeasonalComparisonQuery(),
        VO2MaxTrendQuery(),
        HilliestRunsQuery(),
        ElevationVsPaceQuery(),
        RecoveryAnalysisQuery(),
        RestingHRQuery(),
        HRRangeQuery(),
        HRRecoveryStatsQuery(),
        SleepVsPaceQuery(),
    ]

    static func find(named name: String) -> (any QueryDefinition)? {
        all.first { $0.name == name }
    }
}
