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
@MainActor
final class ModelDownloadManager: NSObject {
    static let shared = ModelDownloadManager()

    /// A background URLSession — not the default configuration — so the OS keeps
    /// the ~770MB transfer running when mirror is backgrounded, suspended, or the
    /// device is locked, instead of the transfer stalling/erroring the moment the
    /// app stops being the foreground process. AppDelegate re-attaches to this same
    /// identifier if iOS relaunches the app to deliver the completion event.
    nonisolated static let backgroundSessionIdentifier = "com.lokesh.mirror.modelDownload"
    /// Set by AppDelegate when iOS wakes the app to hand back a finished background
    /// transfer — must be called once urlSessionDidFinishEvents fires, or the OS
    /// won't grant background time for the next download's completion event.
    var backgroundCompletionHandler: (() -> Void)?

    private nonisolated static let sourceURL = URL(string: "https://huggingface.co/bartowski/google_gemma-3-1b-it-GGUF/resolve/main/google_gemma-3-1b-it-Q4_K_M.gguf")!
    /// Rough estimate only — used to size the progress bar before the server's real
    /// Content-Length is known. Never used to validate a completed file; that check
    /// is against the size the server actually advertised for that specific
    /// download, so it adapts automatically if the hosted file is ever requantized.
    private nonisolated static let estimatedByteCount: Int64 = 806_058_496
    /// A truncated/corrupt file will be nowhere close to this, but an intact gguf of
    /// any quant/version of this model will clear it comfortably.
    private nonisolated static let minimumSaneByteCount: Int64 = 400_000_000
    private static let verifiedByteCountKey = "mirror.modelDownload.verifiedByteCount"
    /// Tracks which model file the app last successfully installed, so a code-side
    /// model swap (new modelFileName shipped in an app update) can be told apart
    /// from a first-ever install.
    private static let lastInstalledModelFileNameKey = "mirror.modelDownload.lastInstalledModelFileName"

    private(set) var state: ModelDownloadState = .notStarted
    /// True when this launch detected a different modelFileName than the one last
    /// installed — i.e. the app shipped a new/updated LLM and the old file was
    /// cleared out. Stays true (across relaunches) until a fresh download completes,
    /// so the prompt to redownload isn't a one-time flash the user can miss.
    private(set) var modelWasUpgraded = false

    private var session: URLSession!
    private var task: URLSessionDownloadTask?
    private var resumeData: Data?

    private override init() {
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: Self.backgroundSessionIdentifier)
        // The user explicitly tapped Download — start now rather than iOS deferring
        // it to whenever it judges conditions "optimal" (Wi-Fi + charging, etc.).
        config.isDiscretionary = false
        // Wake/relaunch the app when the transfer finishes even if it isn't running.
        config.sessionSendsLaunchEvents = true
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)

        let currentFileName = Self.currentModelFileName
        let lastInstalled = UserDefaults.standard.string(forKey: Self.lastInstalledModelFileNameKey)
        modelWasUpgraded = lastInstalled != nil && lastInstalled != currentFileName
        Self.removeStaleModelFiles(keeping: currentFileName)

        if (try? Self.installedModelExists()) == true {
            state = .installed
            // Backfill for installs that predate this tracking key (e.g. already
            // installed before this app update) — otherwise a future model swap
            // would look like a first-ever install instead of an upgrade.
            if lastInstalled == nil {
                UserDefaults.standard.set(currentFileName, forKey: Self.lastInstalledModelFileNameKey)
            }
        }
    }

    private nonisolated static var currentModelFileName: String {
        "\(LocalLLMService.modelFileName).\(LocalLLMService.modelExtension)"
    }

    /// Deletes any leftover model file from a previous LocalLLMService.modelFileName
    /// (an app update that swapped in a different/newer LLM) so it doesn't sit on
    /// disk forever — a stale file never matches the new preferredModelURL(), so it
    /// would otherwise never get cleaned up.
    private nonisolated static func removeStaleModelFiles(keeping currentFileName: String) {
        guard let directory = try? LocalLLMService.modelDirectory(),
              let contents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return }
        for file in contents where file.lastPathComponent != currentFileName {
            try? FileManager.default.removeItem(at: file)
        }
    }

    static func installedModelExists() throws -> Bool {
        let url = try LocalLLMService.preferredModelURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        // If we downloaded this file ourselves, hold it to the exact size the server
        // reported at the time — catches silent truncation on disk. A file that
        // arrived some other way (manual sideload, restored backup) just needs to
        // clear the sanity floor.
        let verified = UserDefaults.standard.object(forKey: verifiedByteCountKey) as? Int64
        if let verified {
            return size == verified
        }
        return size >= minimumSaneByteCount
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
        state = .downloading(progress: 0, bytesWritten: 0, bytesExpected: Self.estimatedByteCount)
        let task = session.downloadTask(with: Self.sourceURL)
        self.task = task
        task.resume()
    }

    @MainActor
    func pauseDownload() {
        task?.cancel { [weak self] data in
            guard let self else { return }
            Task { @MainActor in
                self.resumeData = data
                self.state = .paused(resumable: data != nil)
            }
        }
    }

    @MainActor
    func resumeDownload() {
        guard let resumeData else {
            startDownload()
            return
        }
        state = .downloading(progress: 0, bytesWritten: 0, bytesExpected: Self.estimatedByteCount)
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
    private func finishInstalling(from tempURL: URL, serverExpectedByteCount: Int64) {
        state = .verifying
        do {
            let destination = try LocalLLMService.preferredModelURL()
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: tempURL, to: destination)
            let size = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int64) ?? 0
            // Trust the server's own Content-Length for this download over any
            // hardcoded figure — it's correct even if the hosted file changes.
            // Fall back to the sanity floor only if the server didn't report a length.
            let expected = serverExpectedByteCount > 0 ? serverExpectedByteCount : Self.minimumSaneByteCount
            guard size >= expected else {
                try? FileManager.default.removeItem(at: destination)
                state = .failed("Downloaded file was incomplete (\(size) of \(expected) bytes). Please try again.")
                return
            }
            if serverExpectedByteCount > 0 {
                UserDefaults.standard.set(serverExpectedByteCount, forKey: Self.verifiedByteCountKey)
            }
            UserDefaults.standard.set(Self.currentModelFileName, forKey: Self.lastInstalledModelFileNameKey)
            modelWasUpgraded = false
            state = .installed
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

extension ModelDownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : Self.estimatedByteCount
        let progress = expected > 0 ? Double(totalBytesWritten) / Double(expected) : 0
        Task { @MainActor in
            self.state = .downloading(progress: progress, bytesWritten: totalBytesWritten, bytesExpected: expected)
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The delegate must move the file synchronously before this method returns —
        // the system deletes whatever's at `location` immediately after we return.
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("gemma-3-1b-it-Q4_K_M-\(UUID().uuidString)")
            .appendingPathExtension("gguf")
        // The authoritative total file size, not a hardcoded guess. For a plain GET,
        // countOfBytesExpectedToReceive already is the full size. But a resumed
        // download is a ranged request (HTTP 206) — there, countOfBytesExpectedToReceive
        // is only the *remaining* bytes for that range, not the whole file, so it must
        // come from the Content-Range response header ("bytes start-end/total") instead.
        let serverExpectedByteCount: Int64
        if let contentRange = (downloadTask.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Range"),
           let totalString = contentRange.split(separator: "/").last,
           let total = Int64(totalString) {
            serverExpectedByteCount = total
        } else {
            serverExpectedByteCount = downloadTask.countOfBytesExpectedToReceive
        }
        do {
            try FileManager.default.moveItem(at: location, to: tempURL)
        } catch {
            Task { @MainActor in
                self.state = .failed("Couldn't save downloaded model: \(error.localizedDescription)")
            }
            return
        }
        Task { @MainActor in
            self.finishInstalling(from: tempURL, serverExpectedByteCount: serverExpectedByteCount)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let nsError = error as NSError
        if nsError.code == NSURLErrorCancelled { return }
        Task { @MainActor in
            self.state = .failed(nsError.localizedDescription)
        }
    }

    /// iOS calls this once all queued delegate callbacks for a background session
    /// have been delivered — the completion handler AppDelegate stashed must be
    /// called here, on the main thread, or the app won't get background time for
    /// the next transfer's completion event.
    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            self.backgroundCompletionHandler?()
            self.backgroundCompletionHandler = nil
        }
    }
}
