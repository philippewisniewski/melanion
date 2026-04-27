import Foundation

enum BundledContext {
    nonisolated(unsafe) private static var _biomechanicsReference: String?

    /// The biomechanics reference document injected into every LLM system prompt.
    /// Loaded once from the app bundle and cached.
    static var biomechanicsReference: String {
        if let cached = _biomechanicsReference { return cached }
        guard let url = Bundle.main.url(forResource: "biomechanics-reference", withExtension: "md"),
              let content = try? String(contentsOf: url, encoding: .utf8)
        else {
            return "" // Fail gracefully — LLM will still respond without it
        }
        _biomechanicsReference = content
        return content
    }
}
