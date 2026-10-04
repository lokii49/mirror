import Foundation
import os

/// Timed intervals for Instruments (os_signpost) and `log stream --signpost`, subsystem
/// `com.lokesh.mirror`, category `perf`. Interval names are static strings: never journal text.
/// Used by the Mac performance baseline (`tools/perf/mac_baseline.sh`, Mac performance roadmap, Track 1).
enum PerfSignpost {
    static let signposter = OSSignposter(subsystem: "com.lokesh.mirror", category: "perf")

    @discardableResult
    static func interval<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return try body()
    }

    static func interval<T>(_ name: StaticString, _ body: () async throws -> T) async rethrows -> T {
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return try await body()
    }

    // Cold launch: from App init to the first frame of the main window.
    private nonisolated(unsafe) static var launchState: OSSignpostIntervalState?
    static func beginLaunch() { launchState = signposter.beginInterval("launch") }
    static func endLaunchIfNeeded() {
        guard let state = launchState else { return }
        launchState = nil
        signposter.endInterval("launch", state)
    }
}
