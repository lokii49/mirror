import Foundation

/// mirror patch: keeps GPU decodes away from the moment iOS takes the GPU from a backgrounded app.
///
/// llama.cpp's Metal backend calls `GGML_ABORT` when a command buffer fails
/// (`ggml_metal_synchronize`, ggml-metal-context.m:241 in b6750), and iOS fails every command buffer
/// an app commits once it is in the background. Until 3.1.6 (29) a generation that started in the
/// foreground kept decoding on the GPU after the person left the app, and the whole app aborted
/// (TestFlight crash reports, 2026-10-24/25).
///
/// The app moves the gate with its lifecycle: `.open` while active, `.paused` while inactive (a GPU
/// decode waits instead of committing work that could still be running when the app is backgrounded),
/// `.closed` once in the background (waiting and new GPU decodes throw `LlamaError.gpuUnavailable`
/// instead of committing). CPU-only contexts never consult it. The default is `.open`, so macOS and
/// tests behave as before.
public final class LlamaGPUGate: @unchecked Sendable {
    public enum State: Sendable { case open, paused, closed }

    public static let shared = LlamaGPUGate()

    private let condition = NSCondition()
    private var state: State = .open
    private var inFlight = 0

    public init() {}

    public var currentState: State {
        condition.lock(); defer { condition.unlock() }
        return state
    }

    public func set(_ newState: State) {
        condition.lock()
        state = newState
        condition.broadcast()
        condition.unlock()
    }

    /// Blocks until GPU work may start, then counts it as in flight; throws `LlamaError.gpuUnavailable`
    /// when the gate is (or becomes) closed. Pair with `endGPUWork()`.
    public func beginGPUWork() throws {
        condition.lock()
        defer { condition.unlock() }
        while state == .paused { condition.wait() }
        guard state == .open else { throw LlamaError.gpuUnavailable }
        inFlight += 1
    }

    public func endGPUWork() {
        condition.lock()
        inFlight -= 1
        condition.broadcast()
        condition.unlock()
    }

    /// Waits up to `timeout` for GPU work already started to finish. True when none is in flight.
    @discardableResult
    public func waitUntilIdle(timeout: TimeInterval) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        let deadline = Date().addingTimeInterval(timeout)
        while inFlight > 0 {
            if !condition.wait(until: deadline) { return inFlight == 0 }
        }
        return true
    }
}
