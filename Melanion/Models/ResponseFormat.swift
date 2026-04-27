/// Drives card selection in the UI and format hints in the LLM system prompt.
enum ResponseFormat: String, Codable, Sendable {
    case stat
    case rankedList = "ranked_list"
    case trend
    case detail
}
