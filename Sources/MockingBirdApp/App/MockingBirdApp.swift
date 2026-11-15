import AudioSourceAVFoundation
import AVFoundation
import MockingBirdCore
import SwiftUI

/// The MockingBird macOS app: live microphone key detection and file analysis.
///
/// This is the only place real hardware is wired in. Everything below `ContentView`
/// works through `KeyDetectionDependencies`, so it is testable without a microphone.
@main
struct MockingBirdApp: App {
    @State private var viewModel = KeyDetectionViewModel(dependencies: Self.systemDependencies)
    @State private var handledLaunchArguments = false

    var body: some Scene {
        WindowGroup("MockingBird") {
            ContentView(viewModel: viewModel)
                .task { analyzeLaunchFileOnce() }
        }
        .windowResizability(.contentMinSize)
    }

    /// `open MockingBird.app --args song.wav` analyses `song.wav` straight away.
    private func analyzeLaunchFileOnce() {
        guard !handledLaunchArguments else { return }
        handledLaunchArguments = true
        if let url = LaunchArguments.fileToAnalyze(in: CommandLine.arguments) {
            viewModel.analyzeFile(at: url)
        }
    }

    /// Real capture, real decoding, and the system microphone prompt. Permission is asked
    /// for only when the user presses Listen, never at launch.
    private static let systemDependencies = KeyDetectionDependencies(
        makeLiveSource: { AVFoundationSource() },
        makeFileSource: { AVFoundationFileSource(url: $0) },
        requestMicrophoneAccess: { await AVCaptureDevice.requestAccess(for: .audio) }
    )
}
