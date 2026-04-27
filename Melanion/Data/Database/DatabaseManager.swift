import Foundation
import GRDB

final class DatabaseManager: @unchecked Sendable {
    static let shared = DatabaseManager()

    let db: DatabaseQueue

    private init() {
        do {
            let appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let dbURL = appSupport.appendingPathComponent("melanion.sqlite")

            var config = Configuration()
            config.prepareDatabase { db in
                try db.execute(sql: "PRAGMA journal_mode = WAL")
                try db.execute(sql: "PRAGMA synchronous = NORMAL")
                try db.execute(sql: "PRAGMA cache_size = -8000") // ~8MB
                try db.execute(sql: "PRAGMA foreign_keys = ON")
            }

            db = try DatabaseQueue(path: dbURL.path, configuration: config)
            try MigrationPlan.migrator.migrate(db)
        } catch {
            fatalError("DatabaseManager failed to initialise: \(error)")
        }
    }
}
