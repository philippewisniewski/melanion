import GRDB

enum MigrationPlan {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial_schema") { db in
            // runs table
            try db.create(table: "runs") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("started_at", .text).notNull().unique()
                t.column("date", .text).notNull()
                t.column("year", .integer).notNull()
                t.column("month", .integer).notNull()
                t.column("hour", .integer).notNull()
                t.column("distance_km", .double).notNull()
                t.column("duration_seconds", .integer).notNull()
                t.column("pace_seconds", .integer).notNull()
                t.column("heart_rate_avg_bpm", .integer)
                t.column("heart_rate_min_bpm", .integer)
                t.column("heart_rate_max_bpm", .integer)
                t.column("cadence_steps_per_min", .integer)
                t.column("ground_contact_time_ms", .double)
                t.column("vertical_oscillation_cm", .double)
                t.column("stride_length_metres", .double)
                t.column("running_power_watts", .integer)
                t.column("active_calories_kcal", .integer)
                t.column("elevation_gain_metres", .double)
                t.column("gap_seconds", .integer)
                t.column("pacing_pattern", .text)
                t.column("start_lat", .double)
                t.column("start_lon", .double)
                t.column("route_polyline", .text)
            }

            // recovery table
            try db.create(table: "recovery") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("run_id", .integer).notNull().references("runs", onDelete: .cascade)
                t.column("period", .text).notNull()
                t.column("sleep_duration_hours", .double)
                t.column("hrv_ms", .double)
                t.column("resting_heart_rate_bpm", .integer)
                t.column("vo2_max_ml_kg_min", .double)
                t.column("heart_rate_recovery_bpm", .integer)
                t.column("respiratory_rate", .double)
                t.column("wrist_temperature_c", .double)
                t.column("oxygen_saturation_pct", .double)
            }

            // route_splits table
            try db.create(table: "route_splits") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("run_id", .integer).notNull().references("runs", onDelete: .cascade)
                t.column("km", .integer).notNull()
                t.column("split_seconds", .integer).notNull()
                t.column("elevation_gain_m", .double).notNull()
                t.column("elevation_loss_m", .double).notNull()
            }

            // Indexes
            try db.create(index: "idx_runs_started_at",     on: "runs",         columns: ["started_at"])
            try db.create(index: "idx_runs_pace",           on: "runs",         columns: ["pace_seconds"])
            try db.create(index: "idx_runs_distance",       on: "runs",         columns: ["distance_km"])
            try db.create(index: "idx_runs_hr_avg",         on: "runs",         columns: ["heart_rate_avg_bpm"])
            try db.create(index: "idx_runs_year",           on: "runs",         columns: ["year"])
            try db.create(index: "idx_runs_month",          on: "runs",         columns: ["month"])
            try db.create(index: "idx_runs_pacing_pattern", on: "runs",         columns: ["pacing_pattern"])
            try db.create(index: "idx_recovery_run_id",     on: "recovery",     columns: ["run_id"])
            try db.create(index: "idx_splits_run_id",       on: "route_splits", columns: ["run_id"])
        }

        // A unique index on (run_id, period) lets INSERT OR REPLACE correctly handle
        // re-seeding without duplicating recovery rows per run per period.
        migrator.registerMigration("v2_recovery_unique_period") { db in
            try db.create(index: "idx_recovery_run_period", on: "recovery",
                          columns: ["run_id", "period"], unique: true)
        }

        // Tracks which milestone notifications have already been delivered so they
        // never fire more than once even across re-seeds.
        migrator.registerMigration("v3_notified_milestones") { db in
            try db.create(table: "notified_milestones") { t in
                t.primaryKey("key", .text)
                t.column("fired_at", .text).notNull()
            }
        }

        return migrator
    }
}
