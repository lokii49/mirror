import XCTest
@testable import mirror

// writing-roadmap.md 1.2's perf gap: generateFollowUp/generateGuidedQuestion are the first LLM
// consumers triggered directly by typing, and the actual GPU-inference cost was never measured —
// isBusy (LLMGenerationQueue) prevents requests from stacking, it doesn't say what a single call
// costs while the user keeps typing through it.
//
// This measures a wall-clock floor, not the answer: the simulator runs llama.cpp on the host
// Mac's CPU/GPU, not an iPhone's Neural Engine/GPU under thermal and power constraints, and iOS
// Simulator apps don't get the same Metal performance profile as a real device. Treat the printed
// number as "at least this long, on unrepresentative hardware" — the on-device measurement this
// item calls for still needs to happen on an actual iPhone.
final class PerformanceLLMXCTests: XCTestCase {

    func test_generateFollowUp_wallClockFloor_simulatorOnly() async throws {
        guard GemmaModelTestSupport.ensureModelInstalled() else {
            throw XCTSkip("dev .gguf not present in this checkout (mirror/LocalModels/)")
        }

        let sampleEntry = """
        Today was long. I kept putting off the thing I actually needed to do and instead \
        cleaned the kitchen twice. Not sure if that's avoidance or just needing to move before \
        sitting still with it.
        """

        let start = CFAbsoluteTimeGetCurrent()
        let result = try await InsightService.generateFollowUp(currentText: sampleEntry)
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000

        print("\n[generateFollowUp] SIMULATOR-ONLY wall-clock floor: \(String(format: "%.0f", elapsedMs))ms, engine=\(result.engine.rawValue)")
        print("  NOT a device measurement — llama.cpp here runs on host Mac CPU/GPU via the")
        print("  simulator, not an iPhone's Neural Engine/GPU under real thermal/power limits.")
        print("  writing-roadmap.md 1.2's on-device keystroke-latency measurement is still open.\n")

        XCTAssertFalse(result.text.isEmpty)
    }
}
