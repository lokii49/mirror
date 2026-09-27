import Testing

/// Parent of every Swift Testing suite that sets LocalLLMService's process-wide test switches
/// (`generateInterceptForTesting`, `forceGemmaForTesting`), uses `InsightGenerationCoordinator.shared`,
/// or runs real generation that reads them. Swift Testing runs sibling suites concurrently in one
/// process, so without this parent one suite's intercept or forced-Gemma flag could land in
/// another suite's test mid-flight; `.serialized` here runs all of the children one at a time.
/// A new suite that touches those switches belongs in an `extension SharedLLMState`.
@Suite(.serialized)
enum SharedLLMState {}
