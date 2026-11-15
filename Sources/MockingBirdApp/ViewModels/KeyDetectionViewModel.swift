import Foundation
import MockingBirdCore
import Observation

/// Runs key detection for the window: live listening or one-off file analysis, never both.
///
/// Each run gets a fresh `AnalysisPipeline` (pipelines own their DSP stack and are not
/// reused). Runs are numbered; a run that has been superseded or stopped can still be
/// finishing in the background, and its late results are ignored by comparing numbers.
///
/// The microphone is never touched until `startListening()` is called.
@MainActor
@Observable
final class KeyDetectionViewModel {
    /// What the app is doing now.
    private(set) var state: DetectionState = .idle
    /// The latest result: updated every hop while listening, the whole-file answer after analysis.
    private(set) var result: KeyResult?

    /// The task driving the current run. Exposed so tests can await completion.
    @ObservationIgnored private(set) var activeTask: Task<Void, Never>?

    @ObservationIgnored private let dependencies: KeyDetectionDependencies
    @ObservationIgnored private let config: AudioConfig
    @ObservationIgnored private var activeSource: (any AudioSource)?
    @ObservationIgnored private var activePipeline: AnalysisPipeline?
    @ObservationIgnored private var runNumber = 0

    /// Shown when microphone access is denied or restricted.
    static let permissionDeniedMessage =
        "MockingBird can't use the microphone. Allow it in System Settings › Privacy & Security › Microphone, then press Listen again."

    /// - Parameters:
    ///   - dependencies: Source factories and the permission request.
    ///   - config: Analysis configuration shared by live and file runs.
    init(dependencies: KeyDetectionDependencies, config: AudioConfig = AudioConfig()) {
        self.dependencies = dependencies
        self.config = config
    }

    /// The rolling window used for live input: about the last 15 s of audio.
    nonisolated static func liveAggregation(for config: AudioConfig) -> ChromaAggregation {
        .rolling(windows: max(1, Int(15 * config.sampleRate / Double(config.hopSize))))
    }

    /// True while a run (permission prompt, listening, or file analysis) is in progress.
    var isBusy: Bool {
        switch state {
        case .requestingPermission, .listening, .analyzingFile: return true
        case .idle, .finished, .failed: return false
        }
    }

    /// True while live capture is requested or running.
    var isListening: Bool {
        state == .listening || state == .requestingPermission
    }

    /// Asks for microphone access, then publishes a rolling result every hop until `stop()`.
    /// Stops any file analysis in progress.
    func startListening() {
        let run = beginRun(state: .requestingPermission)
        let dependencies = dependencies
        let aggregation = Self.liveAggregation(for: config)
        activeTask = Task { [weak self] in
            let granted = await dependencies.requestMicrophoneAccess()
            guard let self, self.runNumber == run else { return }
            guard granted else {
                self.state = .failed(Self.permissionDeniedMessage)
                return
            }
            self.state = .listening
            await self.consume(
                source: dependencies.makeLiveSource(),
                aggregation: aggregation,
                run: run,
                mode: .live
            )
        }
    }

    /// Analyses the whole file and publishes one result for it. Stops listening if active.
    func analyzeFile(at url: URL) {
        let name = url.lastPathComponent
        let run = beginRun(state: .analyzingFile(name))
        let source = dependencies.makeFileSource(url)
        activeTask = Task { [weak self] in
            await self?.consume(source: source, aggregation: .cumulative, run: run, mode: .file(name))
        }
    }

    /// Stops whatever is running and returns to `idle`. Keeps the last result on screen.
    func stop() {
        cancelActiveRun()
        state = .idle
    }

    // MARK: - Private

    private enum Mode {
        case live
        case file(String)
    }

    private func beginRun(state newState: DetectionState) -> Int {
        cancelActiveRun()
        result = nil
        state = newState
        return runNumber
    }

    private func cancelActiveRun() {
        runNumber += 1
        activeSource?.stop()
        if let pipeline = activePipeline {
            Task { await pipeline.stop() }
        }
        activeTask?.cancel()
        activeSource = nil
        activePipeline = nil
        activeTask = nil
    }

    private func consume(source: any AudioSource, aggregation: ChromaAggregation, run: Int, mode: Mode) async {
        do {
            let pipeline = try AnalysisPipeline(source: source, config: config, aggregation: aggregation)
            guard runNumber == run else { return }
            activeSource = source
            activePipeline = pipeline

            var last: KeyResult?
            for try await next in try await pipeline.start() {
                guard runNumber == run else { return }
                last = next
                if case .live = mode {
                    result = next
                }
            }
            guard runNumber == run else { return }
            finish(mode: mode, last: last)
        } catch {
            guard runNumber == run else { return }
            state = .failed(failureMessage(for: error, mode: mode))
        }
        activeSource = nil
        activePipeline = nil
    }

    private func finish(mode: Mode, last: KeyResult?) {
        switch mode {
        case .live:
            // The source ended on its own (device gone quiet or closed): nothing left to show live.
            state = .idle
        case .file(let name):
            guard let last else {
                let seconds = Double(config.windowSize) / config.sampleRate
                state = .failed(
                    "Not enough audio in \(name) to detect a key (need at least \(String(format: "%.2f", seconds)) s)."
                )
                return
            }
            result = last
            state = .finished(name)
        }
    }

    private func failureMessage(for error: Error, mode: Mode) -> String {
        switch mode {
        case .live: return "Listening stopped: \(error.userFacingDescription)"
        case .file(let name): return "Could not analyse \(name): \(error.userFacingDescription)"
        }
    }
}
