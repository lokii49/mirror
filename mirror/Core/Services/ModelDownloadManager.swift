import Foundation
import SwiftUI

enum ModelDownloadState: Equatable {
    case notStarted
    case downloading(progress: Double, bytesWritten: Int64, bytesExpected: Int64)
    case paused(resumable: Bool, bytesWritten: Int64, bytesExpected: Int64)
    case verifying
    case installed
    case failed(String)
}

/// Downloads the Gemma 3 1B model from models.mirrornotes.org into Application Support on
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

    /// Our own copy (Cloudflare R2, immutable cache header) of bartowski/google_gemma-3-1b-it-GGUF
    /// `google_gemma-3-1b-it-Q4_K_M.gguf` at commit 116f762, byte for byte. Never put different bytes
    /// at this URL: a new file gets a new path and a new `modelSHA256`.
    private nonisolated static let sourceURL = URL(string: "https://models.mirrornotes.org/gemma3/google_gemma-3-1b-it-Q4_K_M.gguf")!
    /// SHA-256 of that file (806,058,496 bytes). A download that doesn't match is deleted, never installed.
    nonisolated static let modelSHA256 = "12bf0fff8815d5f73a3c9b586bd8fee8e7b248c935de70dec367679873d0f29d"
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
    /// Where a paused or failed transfer can pick up again. Also kept on disk
    /// (`resumeDataURL`), so a pause survives the app being quit.
    private var resumeData: Data?
    /// Last progress shown, so Pause and Resume don't jump the bar back to 0.
    private var lastBytesWritten: Int64 = 0
    private var lastBytesExpected: Int64 = estimatedByteCount
    /// Pause shows at once, but the background session hands back the resume data a
    /// moment later. A Resume tapped in between waits for it instead of starting at 0.
    private var pauseInFlight = false
    private var resumeAfterPause = false
    private static let resumeBytesWrittenKey = "mirror.modelDownload.resumeBytesWritten"
    private static let resumeBytesExpectedKey = "mirror.modelDownload.resumeBytesExpected"

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
            Self.clearStoredResumeData()
        } else if let data = Self.storedResumeData() {
            resumeData = data
            lastBytesWritten = (UserDefaults.standard.object(forKey: Self.resumeBytesWrittenKey) as? Int64) ?? 0
            lastBytesExpected = (UserDefaults.standard.object(forKey: Self.resumeBytesExpectedKey) as? Int64) ?? Self.estimatedByteCount
            state = .paused(resumable: true, bytesWritten: lastBytesWritten, bytesExpected: lastBytesExpected)
        }
        // A transfer from before the app was quit keeps running in the background
        // session. Adopt it, or tapping Download would start a second one from 0.
        session.getAllTasks { tasks in
            guard let running = tasks.compactMap({ $0 as? URLSessionDownloadTask }).first(where: { $0.state == .running })
            else { return }
            Task { @MainActor in self.adopt(running) }
        }
    }

    private func adopt(_ running: URLSessionDownloadTask) {
        guard task == nil, !isReady else { return }
        task = running
        resumeData = nil
        Self.clearStoredResumeData()
        let expected = running.countOfBytesExpectedToReceive > 0 ? running.countOfBytesExpectedToReceive : lastBytesExpected
        let written = max(running.countOfBytesReceived, lastBytesWritten)
        showProgress(written: written, expected: expected)
    }

    /// Not in the model directory: `removeStaleModelFiles` deletes everything else there.
    private nonisolated static func resumeDataURL() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("ModelDownload.resumedata")
    }

    private static func storedResumeData() -> Data? {
        guard let url = try? resumeDataURL() else { return nil }
        return try? Data(contentsOf: url)
    }

    private func storeResumeData(_ data: Data?) {
        resumeData = data
        guard let data else {
            Self.clearStoredResumeData()
            return
        }
        if let url = try? Self.resumeDataURL() {
            try? data.write(to: url, options: .atomic)
        }
        UserDefaults.standard.set(lastBytesWritten, forKey: Self.resumeBytesWrittenKey)
        UserDefaults.standard.set(lastBytesExpected, forKey: Self.resumeBytesExpectedKey)
    }

    private static func clearStoredResumeData() {
        if let url = try? resumeDataURL() {
            try? FileManager.default.removeItem(at: url)
        }
        UserDefaults.standard.removeObject(forKey: resumeBytesWrittenKey)
        UserDefaults.standard.removeObject(forKey: resumeBytesExpectedKey)
    }

    private func showProgress(written: Int64, expected: Int64) {
        lastBytesWritten = written
        lastBytesExpected = expected
        let progress = expected > 0 ? Double(written) / Double(expected) : 0
        state = .downloading(progress: progress, bytesWritten: written, bytesExpected: expected)
    }

    private nonisolated static var currentModelFileName: String {
        "\(LocalLLMService.modelFileName).\(LocalLLMService.modelExtension)"
    }

    /// Deletes any leftover model file from a previous LocalLLMService.modelFileName
    /// (an app update that swapped in a different/newer LLM) so it doesn't sit on
    /// disk forever — a stale file never matches the new preferredModelURL(), so it
    /// would otherwise never get cleaned up.
    ///
    /// Every model file the app owns lives in this directory and must be in `keptFileNames`:
    /// 3.1.0 kept only Gemma's, so each launch deleted Ask's search model (EmbeddingGemma) and
    /// it downloaded again.
    nonisolated static func removeStaleModelFiles(keeping currentFileName: String, in directory: URL? = nil) {
        guard let directory = directory ?? (try? LocalLLMService.modelDirectory()),
              let contents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return }
        let keptFileNames: Set<String> = [currentFileName, SemanticSearchService.modelFileName]
        for file in contents where !keptFileNames.contains(file.lastPathComponent) {
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
        storeResumeData(nil)
        showProgress(written: 0, expected: Self.estimatedByteCount)
        let task = session.downloadTask(with: Self.sourceURL)
        self.task = task
        task.resume()
    }

    @MainActor
    func pauseDownload() {
        guard let pausing = task else { return }
        task = nil
        state = .paused(resumable: true, bytesWritten: lastBytesWritten, bytesExpected: lastBytesExpected)
        pauseInFlight = true
        pausing.cancel { [weak self] data in
            guard let self else { return }
            Task { @MainActor in
                guard self.pauseInFlight else { return }
                self.pauseInFlight = false
                self.storeResumeData(data)
                self.state = .paused(resumable: data != nil, bytesWritten: self.lastBytesWritten, bytesExpected: self.lastBytesExpected)
                if self.resumeAfterPause {
                    self.resumeAfterPause = false
                    self.resumeDownload()
                }
            }
        }
    }

    /// Resume, and Try Again after a network error: continues from the saved byte
    /// offset when there is one, else starts over.
    @MainActor
    func resumeDownload() {
        switch state {
        case .downloading, .verifying:
            return
        default:
            break
        }
        if pauseInFlight {
            resumeAfterPause = true
            return
        }
        guard let resumeData else {
            startDownload()
            return
        }
        showProgress(written: lastBytesWritten, expected: lastBytesExpected)
        let task = session.downloadTask(withResumeData: resumeData)
        self.task = task
        storeResumeData(nil)
        task.resume()
    }

    #if DEBUG
    /// Removes the installed model and resets state, so the download flow can be
    /// re-tested from the "AI model needed" card without reinstalling the app.
    @MainActor
    func deleteInstalledModelForTesting() {
        task?.cancel()
        task = nil
        storeResumeData(nil)
        if let url = try? LocalLLMService.preferredModelURL() {
            try? FileManager.default.removeItem(at: url)
        }
        state = .notStarted
    }
    #endif

    @MainActor
    func cancelDownload() {
        pauseInFlight = false
        resumeAfterPause = false
        task?.cancel()
        task = nil
        storeResumeData(nil)
        state = .notStarted
    }

    @MainActor
    private func finishInstalling(from tempURL: URL, serverExpectedByteCount: Int64, sha256: String?) {
        guard sha256 == Self.modelSHA256 else {
            try? FileManager.default.removeItem(at: tempURL)
            storeResumeData(nil)
            state = .failed(String(localized: "Downloaded model didn't match its fingerprint. Please try again."))
            return
        }
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
                state = .failed(String(localized: "Downloaded file was incomplete (\(size) of \(expected) bytes). Please try again."))
                return
            }
            if serverExpectedByteCount > 0 {
                UserDefaults.standard.set(serverExpectedByteCount, forKey: Self.verifiedByteCountKey)
            }
            UserDefaults.standard.set(Self.currentModelFileName, forKey: Self.lastInstalledModelFileNameKey)
            modelWasUpgraded = false
            task = nil
            storeResumeData(nil)
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
        var written = totalBytesWritten
        var expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : Self.estimatedByteCount
        // A resumed transfer (HTTP 206) may count only the remaining range. If the
        // expected bytes are fewer than the whole file, add back what was already on disk.
        if let total = Self.contentRangeTotal(of: downloadTask), totalBytesExpectedToWrite > 0, totalBytesExpectedToWrite < total {
            written += total - totalBytesExpectedToWrite
            expected = total
        }
        let id = downloadTask.taskIdentifier
        Task { @MainActor in
            // Late callbacks from a task that was just paused must not flip the card back to downloading.
            guard self.task?.taskIdentifier == id else { return }
            self.showProgress(written: written, expected: expected)
        }
    }

    #if DEBUG
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didResumeAtOffset fileOffset: Int64, expectedTotalBytes: Int64) {
        print("[ModelDownload] resumed at offset \(fileOffset) of \(expectedTotalBytes)")
    }
    #endif

    /// The whole file's size from a 206's `Content-Range: bytes start-end/total`.
    private nonisolated static func contentRangeTotal(of task: URLSessionTask) -> Int64? {
        guard let contentRange = (task.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Range"),
              let totalString = contentRange.split(separator: "/").last
        else { return nil }
        return Int64(totalString)
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
        let serverExpectedByteCount = Self.contentRangeTotal(of: downloadTask) ?? downloadTask.countOfBytesExpectedToReceive
        do {
            try FileManager.default.moveItem(at: location, to: tempURL)
        } catch {
            Task { @MainActor in
                self.state = .failed(String(localized: "Couldn't save downloaded model: \(error.localizedDescription)"))
            }
            return
        }
        Task { @MainActor in self.state = .verifying }
        // Hashing ~800MB takes seconds, so it runs here on the delegate queue, not the main actor.
        let sha256 = try? SemanticSearchService.sha256(of: tempURL)
        Task { @MainActor in
            self.finishInstalling(from: tempURL, serverExpectedByteCount: serverExpectedByteCount, sha256: sha256)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let nsError = error as NSError
        if nsError.code == NSURLErrorCancelled { return }
        // A dropped connection hands back where it got to, so Try Again can continue from there.
        let data = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        let id = task.taskIdentifier
        Task { @MainActor in
            guard self.task == nil || self.task?.taskIdentifier == id else { return }
            self.task = nil
            self.storeResumeData(data)
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
