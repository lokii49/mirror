import Foundation
import SwiftUI

enum ModelDownloadState: Equatable {
    case notStarted
    case downloading(progress: Double, bytesWritten: Int64, bytesExpected: Int64)
    case paused(resumable: Bool)
    case verifying
    case installed
    case failed(String)
}

/// Downloads the Gemma 3 1B model from Hugging Face into Application Support on
/// demand, instead of shipping it inside the app bundle. The 768MB model file was
/// previously bundled directly into the IPA — this cut the App Store download size
/// by roughly 800MB, since a journaling app with an 800MB install size is a hard
/// bounce for most users before they even open it once.
@Observable
final class ModelDownloadManager: NSObject {
    static let shared = ModelDownloadManager()

    private static let sourceURL = URL(string: "https://huggingface.co/bartowski/google_gemma-3-1b-it-GGUF/resolve/main/google_gemma-3-1b-it-Q4_K_M.gguf")!
    /// From the source repo's file listing — used to validate a completed download
    /// wasn't truncated or corrupted before it's handed to the LLM.
    private static let expectedByteCount: Int64 = 806_058_496

    private(set) var state: ModelDownloadState = .notStarted

    private var session: URLSession!
    private var task: URLSessionDownloadTask?
    private var resumeData: Data?

    private override init() {
        super.init()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        if (try? Self.installedModelExists()) == true {
            state = .installed
        }
    }

    static func installedModelExists() throws -> Bool {
        let url = try LocalLLMService.preferredModelURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        return size == expectedByteCount
    }

    var isReady: Bool {
        if case .installed = state { return true }
        return false
    }

    @MainActor
    func startDownload() {
        switch state {
        case .downloading, .verifying:
            return
        default:
            break
        }
        state = .downloading(progress: 0, bytesWritten: 0, bytesExpected: Self.expectedByteCount)
        let task = session.downloadTask(with: Self.sourceURL)
        self.task = task
        task.resume()
    }

    @MainActor
    func pauseDownload() {
        task?.cancel { [weak self] data in
            Task { @MainActor in
                self?.resumeData = data
                self?.state = .paused(resumable: data != nil)
            }
        }
    }

    @MainActor
    func resumeDownload() {
        guard let resumeData else {
            startDownload()
            return
        }
        state = .downloading(progress: 0, bytesWritten: 0, bytesExpected: Self.expectedByteCount)
        let task = session.downloadTask(withResumeData: resumeData)
        self.task = task
        self.resumeData = nil
        task.resume()
    }

    #if DEBUG
    /// Removes the installed model and resets state, so the download flow can be
    /// re-tested from the "AI model needed" card without reinstalling the app.
    @MainActor
    func deleteInstalledModelForTesting() {
        task?.cancel()
        task = nil
        resumeData = nil
        if let url = try? LocalLLMService.preferredModelURL() {
            try? FileManager.default.removeItem(at: url)
        }
        state = .notStarted
    }
    #endif

    @MainActor
    func cancelDownload() {
        task?.cancel()
        task = nil
        resumeData = nil
        state = .notStarted
    }

    @MainActor
    private func finishInstalling(from tempURL: URL) {
        state = .verifying
        do {
            let destination = try LocalLLMService.preferredModelURL()
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: tempURL, to: destination)
            let size = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int64) ?? 0
            guard size == Self.expectedByteCount else {
                try? FileManager.default.removeItem(at: destination)
                state = .failed("Downloaded file was incomplete (\(size) of \(Self.expectedByteCount) bytes). Please try again.")
                return
            }
            state = .installed
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

extension ModelDownloadManager: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : Self.expectedByteCount
        let progress = expected > 0 ? Double(totalBytesWritten) / Double(expected) : 0
        Task { @MainActor in
            self.state = .downloading(progress: progress, bytesWritten: totalBytesWritten, bytesExpected: expected)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The delegate must move the file synchronously before this method returns —
        // the system deletes whatever's at `location` immediately after we return.
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("gemma-3-1b-it-Q4_K_M-\(UUID().uuidString)")
            .appendingPathExtension("gguf")
        do {
            try FileManager.default.moveItem(at: location, to: tempURL)
        } catch {
            Task { @MainActor in
                self.state = .failed("Couldn't save downloaded model: \(error.localizedDescription)")
            }
            return
        }
        Task { @MainActor in
            self.finishInstalling(from: tempURL)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let nsError = error as NSError
        if nsError.code == NSURLErrorCancelled { return }
        Task { @MainActor in
            self.state = .failed(nsError.localizedDescription)
        }
    }
}
