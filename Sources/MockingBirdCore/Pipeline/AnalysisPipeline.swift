import Foundation

/// Orchestrates the full key-detection pipeline for a single analysis job.
///
/// Each pipeline exclusively owns its DSP stack — `FFTProcessor`, `ChromaExtractor`,
/// and `KeyDetector` are never shared between pipeline instances.
///
/// Usage:
/// ```swift
/// let pipeline = try AnalysisPipeline(source: fileSource, aggregation: .cumulative)
/// var last: KeyResult?
/// for try await result in try await pipeline.start() {
///     last = result // with .cumulative, the final result covers the whole input
/// }
/// ```
public actor AnalysisPipeline {
    private let source: any AudioSource
    private let config: AudioConfig
    private let aggregation: ChromaAggregation
    private let fft: FFTProcessor
    private let chroma: ChromaExtractor
    private let detector: KeyDetector
    private var reader: Task<Void, Never>?

    /// - Parameters:
    ///   - source: Audio source providing raw PCM chunks.
    ///   - config: Pipeline configuration. Defaults to standard 44100/4096.
    ///   - library: Profile library for key detection. Defaults to built-in set.
    ///   - aggregation: How chroma is combined across windows before detection.
    /// - Throws: `PipelineError.fftSetupFailed` if the FFT transform cannot be allocated.
    public init(
        source: any AudioSource,
        config: AudioConfig = AudioConfig(),
        library: ProfileLibrary = .default,
        aggregation: ChromaAggregation = .cumulative
    ) throws {
        if case .rolling(let windows) = aggregation {
            precondition(windows >= 1, "rolling aggregation needs at least 1 window, got \(windows)")
        }
        self.source = source
        self.config = config
        self.aggregation = aggregation
        self.fft = try FFTProcessor(config: config)
        self.chroma = ChromaExtractor(config: config)
        self.detector = KeyDetector(library: library, numAlternates: config.numAlternates)
    }

    /// Starts capture and returns an async stream of `KeyResult` values.
    ///
    /// One `KeyResult` is emitted per hop once a full window is available, so an N-sample
    /// input yields `(N - windowSize) / hopSize + 1` results (none if N < windowSize).
    /// Each result's `timestamp` is the seconds of audio consumed at the end of its window,
    /// `(windowIndex * hopSize + windowSize) / sampleRate`. The stream finishes when the
    /// source finishes, and fails with `PipelineError` if the source fails. If the consumer
    /// stops iterating, the reader is cancelled and the source stopped.
    ///
    /// - Throws: `PipelineError` or `AudioSourceError` if the source cannot start.
    public func start() throws -> AsyncThrowingStream<KeyResult, Error> {
        let audio = try source.start(sampleRate: config.sampleRate)
        let (results, continuation) = AsyncThrowingStream<KeyResult, Error>.makeStream()
        let task = Task { await self.run(audio, into: continuation) }
        let source = self.source
        continuation.onTermination = { _ in
            task.cancel()
            source.stop()
        }
        reader = task
        return results
    }

    /// Stops audio capture and ends the result stream.
    public func stop() {
        source.stop()
        reader?.cancel()
    }

    // MARK: - Private

    private func run(
        _ audio: AsyncThrowingStream<[Float], Error>,
        into continuation: AsyncThrowingStream<KeyResult, Error>.Continuation
    ) async {
        var buffer: [Float] = []
        var windowStart = 0
        var windowIndex = 0
        var accumulator = ChromaAccumulator(aggregation: aggregation)

        do {
            for try await chunk in audio {
                guard !Task.isCancelled else { break }
                buffer.append(contentsOf: chunk)

                while buffer.count - windowStart >= config.windowSize {
                    let window = Array(buffer[windowStart..<(windowStart + config.windowSize)])
                    let step = accumulator.adding(chroma.extractEnergy(fft.process(window)))
                    accumulator = step.accumulator
                    continuation.yield(detector.detect(
                        chroma.normalized(step.aggregate),
                        timestamp: timestamp(ofWindow: windowIndex)
                    ))
                    windowStart += config.hopSize
                    windowIndex += 1
                }
                // Drop consumed samples once they outnumber a window, so the buffer
                // stays small without shifting it on every hop.
                if windowStart >= config.windowSize {
                    buffer.removeFirst(windowStart)
                    windowStart = 0
                }
            }
            continuation.finish()
        } catch let error as PipelineError {
            continuation.finish(throwing: error)
        } catch let error as AudioSourceError {
            continuation.finish(throwing: PipelineError.audioSourceFailed(
                error,
                ErrorContext(operation: "audio stream", component: "AnalysisPipeline")
            ))
        } catch {
            continuation.finish(throwing: PipelineError.pipelineStopped(
                ErrorContext(
                    operation: "audio stream",
                    component: "AnalysisPipeline",
                    underlyingDescription: String(describing: error)
                )
            ))
        }
    }

    private func timestamp(ofWindow index: Int) -> Double {
        Double(index * config.hopSize + config.windowSize) / config.sampleRate
    }
}
