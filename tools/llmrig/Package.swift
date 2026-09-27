// swift-tools-version: 6.0
// Off-device Gemma test rig. Builds against the app's own vendored SwiftLlama package (same
// patched sources, same llama.cpp b6102 xcframework), so generations here match the app's Gemma
// path, at Metal speed on a Mac instead of ~25s/generation on the simulator's CPU path.
import PackageDescription

let package = Package(
    name: "llmrig",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../../Packages/SwiftLlama"),
    ],
    targets: [
        .executableTarget(
            name: "rig",
            dependencies: [
                .product(name: "SwiftLlama", package: "SwiftLlama"),
                .product(name: "LlamaCpp", package: "SwiftLlama"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
