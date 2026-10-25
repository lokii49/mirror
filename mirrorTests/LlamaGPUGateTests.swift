import XCTest
import SwiftLlama

// SwiftLlama patch 9 (LlamaGPUGate): GPU decodes wait while the app is inactive and throw once it is in
// the background, instead of committing Metal work llama.cpp would abort on. The simulator never decodes
// on the GPU, so the gate is tested on its own here; the device check is in PATCHES.md.
final class LlamaGPUGateTests: XCTestCase {

    func test_openGateLetsWorkThroughAndCountsIt() throws {
        let gate = LlamaGPUGate()
        try gate.beginGPUWork()
        XCTAssertFalse(gate.waitUntilIdle(timeout: 0.05), "work in flight")
        gate.endGPUWork()
        XCTAssertTrue(gate.waitUntilIdle(timeout: 0.05))
    }

    func test_closedGateThrowsGPUUnavailable() {
        let gate = LlamaGPUGate()
        gate.set(.closed)
        XCTAssertThrowsError(try gate.beginGPUWork()) { error in
            guard case LlamaError.gpuUnavailable = error else { return XCTFail("\(error)") }
        }
        XCTAssertTrue(gate.waitUntilIdle(timeout: 0.05), "a refused decode isn't counted")
    }

    func test_pausedGateWaitsUntilOpened() {
        let gate = LlamaGPUGate()
        gate.set(.paused)
        let started = expectation(description: "work started after the gate opened")
        DispatchQueue.global().async {
            do { try gate.beginGPUWork(); gate.endGPUWork(); started.fulfill() } catch { XCTFail("\(error)") }
        }
        Thread.sleep(forTimeInterval: 0.2)
        gate.set(.open)
        wait(for: [started], timeout: 2)
    }

    func test_pausedGateThrowsWhenTheAppGoesToTheBackground() {
        let gate = LlamaGPUGate()
        gate.set(.paused)
        let refused = expectation(description: "waiting work refused once closed")
        DispatchQueue.global().async {
            do { try gate.beginGPUWork(); XCTFail("should not start") } catch LlamaError.gpuUnavailable { refused.fulfill() } catch { XCTFail("\(error)") }
        }
        Thread.sleep(forTimeInterval: 0.2)
        gate.set(.closed)
        wait(for: [refused], timeout: 2)
    }

    func test_waitUntilIdleWaitsForWorkInFlight() throws {
        let gate = LlamaGPUGate()
        try gate.beginGPUWork()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { gate.endGPUWork() }
        XCTAssertTrue(gate.waitUntilIdle(timeout: 2))
    }
}
