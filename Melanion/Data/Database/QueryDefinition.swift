import Foundation
import GRDB

/// A row of query results — keys are column names, values are Any? for formatter compatibility.
typealias QueryRow = [String: Any?]

protocol QueryDefinition: Sendable {
    /// Unique snake_case identifier — the classifier routes to this name.
    var name: String { get }
    /// Natural language description — used verbatim in the classifier prompt.
    /// Write as: "Return the N most recent runs with date, distance, pace, and heart rate."
    var description: String { get }
    /// Format hint that shapes LLM response style and drives card selection in the UI.
    var format: ResponseFormat { get }
    /// Execute the query and return rows. Params keys match what the classifier extracts.
    func execute(db: Database, params: [String: String]) throws -> [QueryRow]
}
