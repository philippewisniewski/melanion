import Testing
import GRDB
@testable import Melanion

struct DatabaseMigrationTests {

    @Test func migrationCreatesAllTables() throws {
        let db = try DatabaseQueue()
        try MigrationPlan.migrator.migrate(db)

        try db.read { db in
            let tables = try String.fetchAll(db, sql: """
                SELECT name FROM sqlite_master
                WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'grdb_%'
                ORDER BY name
                """)
            #expect(tables.contains("runs"))
            #expect(tables.contains("recovery"))
            #expect(tables.contains("route_splits"))
        }
    }

    @Test func runsTableHasCorrectColumns() throws {
        let db = try DatabaseQueue()
        try MigrationPlan.migrator.migrate(db)

        try db.read { db in
            let columns = try db.columns(in: "runs").map(\.name)
            let required = [
                "id", "started_at", "date", "year", "month", "hour",
                "distance_km", "duration_seconds", "pace_seconds",
                "heart_rate_avg_bpm", "heart_rate_min_bpm", "heart_rate_max_bpm",
                "cadence_steps_per_min", "ground_contact_time_ms",
                "vertical_oscillation_cm", "stride_length_metres",
                "running_power_watts", "active_calories_kcal",
                "elevation_gain_metres", "pacing_pattern",
                "start_lat", "start_lon", "route_polyline"
            ]
            for col in required {
                #expect(columns.contains(col), "Missing column: \(col)")
            }
        }
    }

    @Test func recoveryTableHasCorrectColumns() throws {
        let db = try DatabaseQueue()
        try MigrationPlan.migrator.migrate(db)

        try db.read { db in
            let columns = try db.columns(in: "recovery").map(\.name)
            let required = [
                "id", "run_id", "period",
                "sleep_duration_hours", "hrv_ms", "resting_heart_rate_bpm",
                "vo2_max_ml_kg_min", "heart_rate_recovery_bpm",
                "respiratory_rate", "wrist_temperature_c", "oxygen_saturation_pct"
            ]
            for col in required {
                #expect(columns.contains(col), "Missing column: \(col)")
            }
        }
    }

    @Test func routeSplitsTableHasCorrectColumns() throws {
        let db = try DatabaseQueue()
        try MigrationPlan.migrator.migrate(db)

        try db.read { db in
            let columns = try db.columns(in: "route_splits").map(\.name)
            let required = [
                "id", "run_id", "km", "split_seconds",
                "elevation_gain_m", "elevation_loss_m"
            ]
            for col in required {
                #expect(columns.contains(col), "Missing column: \(col)")
            }
        }
    }

    @Test func migrationIsIdempotent() throws {
        let db = try DatabaseQueue()
        // Running twice must not throw
        try MigrationPlan.migrator.migrate(db)
        try MigrationPlan.migrator.migrate(db)
    }
}
