// swift-tools-version: 6.1
// Vendored from github.com/lokii49/swift-llama-cpp at a79abb8 (MIT, Piotr Gorzelany — see LICENSE)
// on 2026-09-27 so mirror can patch it without publishing a fork release. Local changes are
// listed in PATCHES.md. Same prebuilt llama.cpp as before: keep llamaVersion/llamaChecksum in sync
// with any llama.cpp upgrade (and tools/llmrig, which builds against this package).
import PackageDescription

let llamaVersion = "b6750"
let llamaChecksum = "769478a7997c5bc67f5f10c4593e35b6278e4b6b70279f11ddf4f40d6e85a94f"

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
