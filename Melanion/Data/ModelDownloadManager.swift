import Foundation
import Observation

@MainActor
@Observable
final class ModelDownloadManager: NSObject {
    // MARK: - Published state
    var downloadProgress: Double = 0       // 0.0 – 1.0
    var downloadedBytes: Int64 = 0
    var totalBytes: Int64 = 0
    var state: DownloadState = .idle

    enum DownloadState: Equatable {
        case idle
        case downloading
        case paused
        case complete
        case failed(String)
    }

    // MARK: - Private
    private var downloadTask: URLSessionDownloadTask?
    private var resumeData: Data?
    // Implicitly unwrapped: URLSession requires `self` as delegate during init (two-phase init).
    private var urlSession: URLSession!

    // MARK: - Init
    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.allowsCellularAccess = true
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    // MARK: - Public API

    /// Start or resume the model download
    func startDownload() {
        guard state != .downloading && state != .complete else { return }
        state = .downloading

        if let resumeData {
            downloadTask = urlSession.downloadTask(withResumeData: resumeData)
        } else {
            downloadTask = urlSession.downloadTask(with: ModelStore.modelCDNURL)
        }
        downloadTask?.resume()
    }

    /// Pause the download, preserving resume data
    func pauseDownload() {
        downloadTask?.cancel(byProducingResumeData: { [weak self] data in
            Task { @MainActor in
                self?.resumeData = data
                self?.state = .paused
            }
        })
    }
}

// MARK: - URLSessionDownloadDelegate
extension ModelDownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let progress: Double = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            : 0

        Task { @MainActor in
            self.downloadedBytes = totalBytesWritten
            self.totalBytes = totalBytesExpectedToWrite
            self.downloadProgress = progress
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            let destination = try ModelStore.modelURL
            // Remove any existing partial file
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)

            Task { @MainActor in
                self.state = .complete
            }
        } catch {
            Task { @MainActor in
                self.state = .failed(error.localizedDescription)
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }

        // NSURLErrorCancelled means the user paused — resume data is handled in pauseDownload()
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled else { return }

        let captured = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data

        Task { @MainActor in
            if let captured {
                self.resumeData = captured
            }
            self.state = .failed(error.localizedDescription)
        }
    }
}
