import Foundation
import MockingBirdCore
import MockingBirdTestSupport
import Testing
@testable import MockingBirdApp

@MainActor
@Suite struct KeyDetectionViewModelTests {
    private let songURL = URL(fileURLWithPath: "/tmp/song.wav")

    private func makeViewModel(
        live: @escaping @Sendable () -> any AudioSource = { SyntheticSource(samples: []) },
        file: @escaping @Sendable (URL) -> any AudioSource = { _ in SyntheticSource(samples: []) },
        permission: @escaping @Sendable () async -> Bool = { true }
    ) -> KeyDetectionViewModel {
        KeyDetectionViewModel(dependencies: KeyDetectionDependencies(
            makeLiveSource: live,
            makeFileSource: file,
            requestMicrophoneAccess: permission
        ))
    }

    @Test func startsIdleWithNoResult() {
        let viewModel = makeViewModel()
        #expect(viewModel.state == .idle)
        #expect(viewModel.result == nil)
    }

    @Test func fileAnalysisOfCMajorCadenceFinishesInC() async throws {
        let cadence = ToneSynth.majorCadence(root: 48)
        let viewModel = makeViewModel(file: { _ in SyntheticSource(samples: cadence) })

        viewModel.analyzeFile(at: songURL)
        #expect(viewModel.state == .analyzingFile("song.wav"))
        await viewModel.activeTask?.value

        #expect(viewModel.state == .finished("song.wav"))
        let result = try #require(viewModel.result)
        #expect(result.key == .c)
    }

    @Test func fileSourceReceivesTheDroppedURL() async {
        let received = URLBox()
        let viewModel = makeViewModel(file: { url in
            received.set(url)
            return SyntheticSource(samples: ToneSynth.majorCadence(root: 48))
        })
        viewModel.analyzeFile(at: songURL)
        await viewModel.activeTask?.value
        #expect(received.value == songURL)
    }

    @Test func listeningPublishesResultsAndStopReturnsToIdle() async {
        let source = HeldOpenSource(samples: ToneSynth.majorCadence(root: 48))
        let viewModel = makeViewModel(live: { source })

        viewModel.startListening()
        #expect(await eventually { viewModel.state == .listening })
        #expect(await eventually { viewModel.result != nil })

        viewModel.stop()
        #expect(viewModel.state == .idle)
        #expect(source.stopCount >= 1)
    }

    @Test func listeningAsksForPermissionFirst() async {
        let gate = PermissionGate()
        let viewModel = makeViewModel(
            live: { HeldOpenSource(samples: []) },
            permission: { await gate.wait() }
        )
        viewModel.startListening()
        #expect(viewModel.state == .requestingPermission)
        await gate.open(granted: true)
        #expect(await eventually { viewModel.state == .listening })
        viewModel.stop()
    }

    @Test func deniedPermissionFails() async throws {
        let viewModel = makeViewModel(permission: { false })
        viewModel.startListening()
        await viewModel.activeTask?.value

        guard case .failed(let message) = viewModel.state else {
            Issue.record("expected failed, got \(viewModel.state)")
            return
        }
        #expect(message.contains("System Settings"))
    }

    @Test func failingSourceReportsItsDescription() async {
        let failing = FailingSource(
            samples: ToneSynth.majorCadence(root: 48),
            error: .deviceDisconnected
        )
        let viewModel = makeViewModel(live: { failing })
        viewModel.startListening()
        await viewModel.activeTask?.value

        guard case .failed(let message) = viewModel.state else {
            Issue.record("expected failed, got \(viewModel.state)")
            return
        }
        #expect(message.contains(AudioSourceError.deviceDisconnected.description))
    }

    @Test func sourceThatCannotStartReportsItsDescription() async {
        struct UnstartableSource: AudioSource {
            func start(sampleRate: Double) throws -> AsyncThrowingStream<[Float], Error> {
                throw AudioSourceError.formatUnsupported
            }
            func stop() {}
        }
        let viewModel = makeViewModel(file: { _ in UnstartableSource() })
        viewModel.analyzeFile(at: songURL)
        await viewModel.activeTask?.value
        #expect(viewModel.state == .failed(
            "Could not analyse song.wav: \(AudioSourceError.formatUnsupported.description)"
        ))
    }

    @Test func fileShorterThanOneWindowFailsWithNotEnoughAudio() async {
        let short = ToneSynth.chord([60], duration: 0.05)
        #expect(short.count < AudioConfig().windowSize)
        let viewModel = makeViewModel(file: { _ in SyntheticSource(samples: short) })

        viewModel.analyzeFile(at: songURL)
        await viewModel.activeTask?.value

        guard case .failed(let message) = viewModel.state else {
            Issue.record("expected failed, got \(viewModel.state)")
            return
        }
        #expect(message.lowercased().contains("not enough audio"))
        #expect(viewModel.result == nil)
    }

    @Test func startingFileAnalysisWhileListeningStopsListening() async throws {
        let live = HeldOpenSource(samples: ToneSynth.majorCadence(root: 50))
        let cadence = ToneSynth.majorCadence(root: 48)
        let viewModel = makeViewModel(live: { live }, file: { _ in SyntheticSource(samples: cadence) })

        viewModel.startListening()
        #expect(await eventually { viewModel.result != nil })

        viewModel.analyzeFile(at: songURL)
        #expect(live.stopCount >= 1)
        await viewModel.activeTask?.value

        #expect(viewModel.state == .finished("song.wav"))
        #expect(try #require(viewModel.result).key == .c)
    }

    @Test func startingAFileClearsThePreviousResult() async {
        let cadence = ToneSynth.majorCadence(root: 48)
        let viewModel = makeViewModel(file: { _ in SyntheticSource(samples: cadence) })
        viewModel.analyzeFile(at: songURL)
        await viewModel.activeTask?.value
        #expect(viewModel.result != nil)

        viewModel.analyzeFile(at: songURL)
        #expect(viewModel.result == nil)
        await viewModel.activeTask?.value
    }

    @Test func liveWindowIsAboutFifteenSeconds() {
        let config = AudioConfig()
        #expect(KeyDetectionViewModel.liveAggregation(for: config)
            == .rolling(windows: Int(15 * 44100 / 2048.0)))
    }
}

/// Thread-safe holder for a URL captured inside a `@Sendable` factory.
private final class URLBox: @unchecked Sendable {
    private var stored: URL?
    private let lock = NSLock()
    func set(_ url: URL) { lock.withLock { stored = url } }
    var value: URL? { lock.withLock { stored } }
}

/// Lets a test decide when a permission request completes.
private actor PermissionGate {
    private var waiter: CheckedContinuation<Bool, Never>?
    private var decision: Bool?

    func wait() async -> Bool {
        if let decision { return decision }
        return await withCheckedContinuation { waiter = $0 }
    }

    func open(granted: Bool) {
        decision = granted
        waiter?.resume(returning: granted)
        waiter = nil
    }
}
