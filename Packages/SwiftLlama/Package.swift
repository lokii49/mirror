// swift-tools-version: 6.1
// Vendored from github.com/lokii49/swift-llama-cpp at a79abb8 (MIT, Piotr Gorzelany — see LICENSE)
// on 2026-09-27 so mirror can patch it without publishing a fork release. Local changes are
// listed in PATCHES.md. Same prebuilt llama.cpp as before: keep llamaVersion/llamaChecksum in sync
// with any llama.cpp upgrade (and tools/llmrig, which builds against this package).
import PackageDescription

let llamaVersion = "b6102"
let llamaChecksum = "257b8ffbdda68b377e1b75cd23055b201b0e9a24e18d5a42f2960456776eab8a"

let package = Package(
    name: "SwiftLlama",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "SwiftLlama", targets: ["SwiftLlama"]),
        // The raw llama.cpp C module, for tools/llmrig's tokenizer-level checks.
        .library(name: "LlamaCpp", targets: ["llama"]),
    ],
    targets: [
        .target(name: "SwiftLlama", dependencies: ["llama"]),
        .binaryTarget(
            name: "llama",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/\(llamaVersion)/llama-\(llamaVersion)-xcframework.zip",
            checksum: llamaChecksum
        ),
    ]
)
