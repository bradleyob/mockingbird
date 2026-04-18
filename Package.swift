// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MockingBird",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "MockingBirdCore", targets: ["MockingBirdCore"]),
        .executable(name: "mockingbird", targets: ["MockingBirdCLI"]),
        .executable(name: "mockingbird-server", targets: ["MockingBirdServer"]),
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird-websocket.git", from: "2.0.0"),
    ],
    targets: [
        // MARK: - Core DSP library (no platform imports, compiles on Linux)
        .target(
            name: "MockingBirdCore",
            path: "Sources/MockingBirdCore",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),

        // MARK: - Platform audio sources
        .target(
            name: "AudioSourceAVFoundation",
            dependencies: ["MockingBirdCore"],
            path: "Sources/AudioSourceAVFoundation"
        ),
        .target(
            name: "AudioSourceMiniAudio",
            dependencies: ["MockingBirdCore"],
            path: "Sources/AudioSourceMiniAudio",
            publicHeadersPath: "include"
        ),

        // MARK: - DSP CLI binary
        .executableTarget(
            name: "MockingBirdCLI",
            dependencies: [
                "MockingBirdCore",
                .target(name: "AudioSourceAVFoundation", condition: .when(platforms: [.macOS, .iOS])),
                .target(name: "AudioSourceMiniAudio", condition: .when(platforms: [.linux])),
            ],
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

        // MARK: - Tests
        .testTarget(
            name: "MockingBirdCoreTests",
            dependencies: ["MockingBirdCore"],
            path: "Tests/MockingBirdCoreTests"
        ),
        .testTarget(
            name: "MockingBirdCLITests",
            dependencies: ["MockingBirdCLI"],
            path: "Tests/MockingBirdCLITests"
        ),
    ]
)
