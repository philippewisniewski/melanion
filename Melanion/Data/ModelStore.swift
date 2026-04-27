import Foundation

enum ModelStore {
    /// Filename of the CoreML model package on disk
    static let modelFilename = "gemma4.mlpackage"

    /// CDN URL the model is downloaded from. Replace with actual URL before release.
    static let modelCDNURL = URL(string: "https://cdn.example.com/melanion/\(modelFilename)")!

    /// Stable path in Application Support where the model is stored.
    /// Application Support is not backed up to iCloud and is never deleted by the OS.
    static var modelURL: URL {
        get throws {
            let appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            return appSupport.appendingPathComponent(modelFilename)
        }
    }

    /// Returns true if the model file exists on disk and is non-empty.
    static var isModelDownloaded: Bool {
        guard let url = try? modelURL else { return false }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = attrs?[.size] as? Int ?? 0
        return size > 0
    }
}
