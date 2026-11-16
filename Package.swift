// swift-tools-version: 6.0
import PackageDescription

// Apple-only targets (AVFoundation capture, SwiftUI app) are added to the manifest only
// when building on macOS, so that a plain `swift build` / `swift test` succeeds on Linux.

var products: [Product] = [
    .library(name: "MockingBirdCore", targets: ["MockingBirdCore"]),
    .executable(name: "mockingbird", targets: ["MockingBirdCLI"]),
    .executable(name: "mockingbird-server", targets: ["MockingBirdServer"]),
]

var cliDependencies: [Target.Dependency] = [
    "MockingBirdCore",
    .target(name: "AudioSourceMiniAudio", condition: .when(platforms: [.linux])),
]
#if os(macOS)
cliDependencies.append("AudioSourceAVFoundation")
#endif

var targets: [Target] = [
    // MARK: - Core DSP library (compiles on Linux; Accelerate only behind canImport)
    .target(
        name: "MockingBirdCore",
        path: "Sources/MockingBirdCore",
        swiftSettings: [
            .enableExperimentalFeature("StrictConcurrency"),
        ]
    ),

    // MARK: - miniaudio (vendored single header + mb_ C bridge)
    .target(
        name: "CMiniAudio",
        path: "Sources/CMiniAudio",
        publicHeadersPath: "include",
        cSettings: [
            .headerSearchPath("../../Vendor/miniaudio"),
        ],
        linkerSettings: [
            .linkedLibrary("m", .when(platforms: [.linux])),
            .linkedLibrary("dl", .when(platforms: [.linux])),
            .linkedLibrary("pthread", .when(platforms: [.linux])),
            .linkedFramework("CoreFoundation", .when(platforms: [.macOS])),
            .linkedFramework("CoreAudio", .when(platforms: [.macOS])),
            .linkedFramework("AudioToolbox", .when(platforms: [.macOS])),
        ]
    ),
    .target(
        name: "AudioSourceMiniAudio",
        dependencies: ["MockingBirdCore", "CMiniAudio"],
        path: "Sources/AudioSourceMiniAudio"
    ),

    // MARK: - DSP CLI binary
    .executableTarget(
        name: "MockingBirdCLI",
        dependencies: cliDependencies,
        path: "Sources/MockingBirdCLI"
    ),

    // MARK: - HTTP/WebSocket gateway (no DSP, no MockingBirdCore)
    .executableTarget(
        name: "MockingBirdServer",
        dependencies: [
            .product(name: "Hummingbird", package: "hummingbird"),
            .product(name: "HummingbirdWebSocket", package: "hummingbird-websocket"),
        ],
        path: "Sources/MockingBirdServer"
    ),

    // MARK: - Tests (Swift Testing)
    .target(
        name: "MockingBirdTestSupport",
        dependencies: ["MockingBirdCore"],
        path: "Tests/MockingBirdTestSupport"
    ),
    .testTarget(
        name: "MockingBirdCoreTests",
        dependencies: ["MockingBirdCore", "MockingBirdTestSupport"],
        path: "Tests/MockingBirdCoreTests"
    ),
    .testTarget(
        name: "MockingBirdCLITests",
        dependencies: ["MockingBirdCLI", "MockingBirdTestSupport"],
        path: "Tests/MockingBirdCLITests"
    ),
    .testTarget(
        name: "MockingBirdServerTests",
        dependencies: [
            "MockingBirdServer",
            "MockingBirdCLI",
            "MockingBirdTestSupport",
            .product(name: "HummingbirdTesting", package: "hummingbird"),
            .product(name: "HummingbirdWSClient", package: "hummingbird-websocket"),
        ],
        path: "Tests/MockingBirdServerTests"
    ),
    .testTarget(
        name: "MockingBirdMiniAudioTests",
        dependencies: ["AudioSourceMiniAudio", "MockingBirdTestSupport"],
        path: "Tests/MockingBirdMiniAudioTests"
    ),
]

#if os(macOS)
products.append(.executable(name: "MockingBirdApp", targets: ["MockingBirdApp"]))
targets += [
    .target(
        name: "AudioSourceAVFoundation",
        dependencies: ["MockingBirdCore"],
        path: "Sources/AudioSourceAVFoundation"
    ),
    .executableTarget(
        name: "MockingBirdApp",
        dependencies: ["MockingBirdCore", "AudioSourceAVFoundation"],
        path: "Sources/MockingBirdApp"
    ),
    .testTarget(
        name: "MockingBirdAppTests",
        dependencies: ["MockingBirdApp", "MockingBirdTestSupport"],
        path: "Tests/MockingBirdAppTests"
    ),
]
#endif

let package = Package(
    name: "MockingBird",
    platforms: [
        .macOS(.v14),
    ],
    products: products,
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird-websocket.git", from: "2.0.0"),
    ],
    targets: targets
)
