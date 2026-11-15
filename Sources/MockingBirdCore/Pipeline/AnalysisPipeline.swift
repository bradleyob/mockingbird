import Foundation

/// Orchestrates the full key-detection pipeline for a single analysis job.
///
/// Each pipeline exclusively owns its DSP stack — `FFTProcessor`, `ChromaExtractor`,
/// and `KeyDetector` are never shared between pipeline instances.
///
/// Usage:
/// ```swift
/// let pipeline = try AnalysisPipeline(source: avFoundationSource, config: .init())
/// for try await result in pipeline.start() {
///     print(result) // KeyResult
/// }
/// ```
public actor AnalysisPipeline {
    private let source: any AudioSource
    private let config: AudioConfig
    private let aggregation: ChromaAggregation
    private let fft: FFTProcessor
    private let chroma: ChromaExtractor
    private let detector: KeyDetector

    // Accumulation buffer for hop-based windowing
    private var sampleBuffer: [Float] = []
    private var streamStartTime: Date?

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
        self.source = source
        self.config = config
        self.aggregation = aggregation
        self.fft = try FFTProcessor(config: config)
        self.chroma = ChromaExtractor(config: config)
        self.detector = KeyDetector(library: library, numAlternates: config.numAlternates)
    }

    /// Starts capture and returns an async stream of `KeyResult` values.
    ///
    /// One `KeyResult` is emitted per analysis window (every `config.hopSize` samples).
    /// The stream ends when the audio source stops or throws.
    ///
    /// - Throws: `PipelineError` on DSP or audio source failure.
    public func start() throws -> AsyncThrowingStream<KeyResult, Error> {
        let stream = try source.start(sampleRate: config.sampleRate)
        let capturedConfig = config
        let capturedAggregation = aggregation
        streamStartTime = Date()
        let startTime = streamStartTime!

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var buffer: [Float] = []
                    var accumulator = ChromaAccumulator(aggregation: capturedAggregation)

                    for try await chunk in stream {
                        buffer.append(contentsOf: chunk)

                        while buffer.count >= capturedConfig.windowSize {
                            let window = Array(buffer.prefix(capturedConfig.windowSize))
                            buffer.removeFirst(capturedConfig.hopSize)

                            let timestamp = Date().timeIntervalSince(startTime)
                            let energy = self.chromaEnergy(window: window)
                            let step = accumulator.adding(energy)
                            accumulator = step.accumulator
                            continuation.yield(self.detect(energy: step.aggregate, timestamp: timestamp))
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
                            underlyingDescription: error.localizedDescription
                        )
                    ))
                }
            }
        }
    }

    /// Stops audio capture.
    public func stop() {
        source.stop()
    }

    // MARK: - Private

    private func chromaEnergy(window: [Float]) -> [Float] {
        chroma.extractEnergy(fft.process(window))
    }

    private func detect(energy: [Float], timestamp: Double) -> KeyResult {
        detector.detect(chroma.normalized(energy), timestamp: timestamp)
    }
}
