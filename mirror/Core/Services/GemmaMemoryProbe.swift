#if DEBUG
import Foundation
import Darwin

/// DEBUG-only: `--gemmaMemoryProbe` (with `--perfSeed=N`, so the app runs on the synthetic scratch
/// store with the fixed debug key) measures what Gemma costs in memory inside the real app, then
/// quits. It forces Gemma, runs grounded daily nudges for a few synthetic entries through the app's
/// own `LocalLLMService` path, checks each with `validateGroundedNudge`, and prints `phys_footprint`
/// (what Activity Monitor calls Memory; Metal buffers count, clean mmapped pages don't) before the
/// load, at its peak during each generation (sampled every 50 ms), after each generation, and after
/// `resetContext()`. Nothing is saved: no Insight rows, no notifications. Synthetic text only.
///
/// Result 2026-10-07 (M-series Mac, unsigned Debug): 56 MiB before load, peak 278-317 MiB while
/// generating, 142 MiB after (the model is already released after every call: `generate`'s
/// `defer { service = nil }`), flat across calls, so no leak and nothing to unload on idle.
/// 5/5 grounded nudges passed `validateGroundedNudge`; ~1 s each warm, 13 s cold.
enum GemmaMemoryProbe {
    static var isRequested: Bool { CommandLine.arguments.contains("--gemmaMemoryProbe") }

    private static let cases = [
        "Woke up with a sore throat and stayed in bed most of the day. I cancelled lunch with Priya and felt bad about it. Made soup in the evening and watched an old film.",
        "The interview went better than I expected. They asked about the migration project and I actually had good answers. Now I have to wait until Friday and the waiting is the worst part.",
        "Work was a lot today. Three meetings back to back and the deploy failed twice. I snapped at Leo in the afternoon and I keep thinking about it.",
        "Walked around the lake after dinner. The light on the water was lovely and I didn't look at my phone once. I want more evenings like this.",
        "had a weird day honestly nothing went wrong but i felt flat the whole time and couldnt focus on anything i think i need more sleep",
    ]

    static func footprintMiB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return -1 }
        return Double(info.phys_footprint) / 1_048_576
    }

    private static func log(_ label: String) {
        print(String(format: "[GemmaMemoryProbe] %@: %.1f MiB", label, footprintMiB()))
    }

    @MainActor
    static func run() async {
        LocalLLMService.forceGemmaForTesting = true
        // Let launch settle so the baseline isn't mid-first-frame.
        try? await Task.sleep(for: .seconds(3))
        log("before load")
        var passed = 0
        for (index, text) in cases.enumerated() {
            let entry = Entry(text: text, mood: nil)
            let grounded = InsightService.groundedNudgePlan(recent: [entry], background: [], recentNudges: [])
            let clock = ContinuousClock()
            let start = clock.now
            var peak = footprintMiB()
            let sampler = Task { @MainActor in
                while !Task.isCancelled {
                    peak = max(peak, footprintMiB())
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
            do {
                let result = try await LocalLLMService.shared.generate(
                    systemPrompt: DAILY_NUDGE_GEMMA_INSTRUCTIONS,
                    userMessage: "",
                    task: .dailyNudge,
                    gemmaPlan: grounded.plan,
                    allowFoundationModels: false
                )
                let valid = (try? InsightService.validateGroundedNudge(result.text, quoteOptions: grounded.quoteOptions)) != nil
                if valid { passed += 1 }
                // Synthetic text, so printing the output is fine here (never do this with real entries).
                print("[GemmaMemoryProbe] case \(index + 1) engine=\(result.engine) valid=\(valid) \(clock.now - start): \(result.text)")
            } catch {
                print("[GemmaMemoryProbe] case \(index + 1) error: \(error)")
            }
            sampler.cancel()
            print(String(format: "[GemmaMemoryProbe] case %d peak during generation: %.1f MiB", index + 1, peak))
            log("after case \(index + 1)")
        }
        print("[GemmaMemoryProbe] validateGroundedNudge passed \(passed)/\(cases.count)")
        await LocalLLMService.shared.resetContext()
        try? await Task.sleep(for: .seconds(2))
        log("after resetContext")
        exit(0)
    }
}
#endif
