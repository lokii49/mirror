// swift-tools-version: 6.0
// Off-device Gemma test rig. Same llama.cpp build the app ships (b6102 xcframework, same URL and
// checksum as github.com/lokii49/swift-llama-cpp's Package.swift) and a vendored copy of that
// fork's SwiftLlama sources at a79abb8 — so generations here match the app's Gemma path, at Metal
// speed on a Mac instead of ~25s/generation on the simulator's single-threaded CPU path.
// Keep `llamaVersion`/`llamaChecksum` in sync with the fork whenever Package.resolved moves.
import PackageDescription

let llamaVersion = "b6102"
let llamaChecksum = "257b8ffbdda68b377e1b75cd23055b201b0e9a24e18d5a42f2960456776eab8a"

let package = Package(
    name: "llmrig",
    platforms: [.macOS(.v14)],
    targets: [
        .binaryTarget(
            name: "llama",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/\(llamaVersion)/llama-\(llamaVersion)-xcframework.zip",
            checksum: llamaChecksum
        ),
        .target(name: "SwiftLlama", dependencies: ["llama"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "rig", dependencies: ["SwiftLlama", "llama"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
