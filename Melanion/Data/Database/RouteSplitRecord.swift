import Foundation
import GRDB

struct RouteSplitRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "route_splits"

    var id: Int64?
    var runId: Int64
    var km: Int
    var splitSeconds: Int
    var elevationGainM: Double
    var elevationLossM: Double
}

extension RouteSplitRecord: TableRecord {
    enum Columns: String, ColumnExpression {
        case id, runId = "run_id", km
        case splitSeconds = "split_seconds"
        case elevationGainM = "elevation_gain_m"
        case elevationLossM = "elevation_loss_m"
    }

    static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase
    static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
}
