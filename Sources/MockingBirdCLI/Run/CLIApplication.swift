import Foundation
import MockingBirdCore

/// The `mockingbird` program: parse, pick an input, run the pipeline, write results.
enum CLIApplication {
    /// Seconds of device audio analysed when neither `--duration` nor `--continuous` is given.
    static let defaultDeviceDuration = 10.0
    /// Length of the rolling window used by `--continuous`, in seconds of audio.
    static let rollingWindowSeconds = 15.0

    /// Runs the program and returns its exit status. Failures are reported on stderr.
    static func run(
        arguments: [String],
        stdinIsTerminal: Bool,
        output: ResultWriter = ResultWriter(),
        log: DiagnosticLog = DiagnosticLog()
    ) async -> CLIExitCode {
        do {
            try await execute(arguments: arguments, stdinIsTerminal: stdinIsTerminal, output: output)
            return .ok
        } catch {
            log.error(error.message)
            return error.exitCode
        }
    }

    // MARK: - Private

    private static func execute(
        arguments: [String],
        stdinIsTerminal: Bool,
        output: ResultWriter
    ) async throws(CLIFailure) {
        let options: CLIOptions
        do {
            options = try CLIOptionsParser.parse(arguments)
        } catch {
            throw .usage(error)
        }

        if options.showHelp {
            try write(CLIHelp.usage, to: output)
            return
        }
        if options.showVersion {
            try write(CLIHelp.version, to: output)
            return
        }
        if options.listDevices {
            try write(try DeviceDirectory.inputDeviceNames(), to: output)
            return
        }

        let library = try options.profilesPath.map { path throws(CLIFailure) in
            try ProfileLibraryLoader.load(path: path)
        } ?? .default
        let selection = InputSelection(options: options, stdinIsTerminal: stdinIsTerminal)
        let source = limited(try AudioSourceFactory.makeSource(for: selection), options: options, selection: selection)
        try await analyse(source: source, library: library, options: options, selection: selection, output: output)
    }

    private static func analyse(
        source: any AudioSource,
        library: ProfileLibrary,
        options: CLIOptions,
        selection: InputSelection,
        output: ResultWriter
    ) async throws(CLIFailure) {
        // CLIOptionsParser has already enforced every AudioConfig precondition.
        let config = AudioConfig(
            sampleRate: Double(options.sampleRate),
            windowSize: options.windowSize,
            hopSize: options.hopSize,
            numAlternates: options.alternates,
            zeroPad: options.zeroPad
        )
        let aggregation: ChromaAggregation = options.continuous
            ? .rolling(windows: max(1, Int(rollingWindowSeconds * config.sampleRate / Double(config.hopSize))))
            : .cumulative
        let formatter = ResultFormatter(format: options.format)

        let stream: AsyncThrowingStream<KeyResult, Error>
        do {
            let pipeline = try AnalysisPipeline(source: source, config: config, library: library, aggregation: aggregation)
            stream = try await pipeline.start()
        } catch {
            throw failure(for: error, selection: selection)
        }

        let emitted: Int
        do {
            if options.continuous {
                emitted = try await stream.reduce(0) { count, result in
                    try output.write(line: try formatter.format(result))
                    return count + 1
                }
            } else {
                let last: KeyResult? = try await stream.reduce(nil) { _, result in result }
                if let last {
                    try output.write(line: try formatter.format(last))
                }
                emitted = last == nil ? 0 : 1
            }
        } catch {
            throw failure(for: error, selection: selection)
        }

        guard emitted > 0 else { throw .insufficientAudio }
    }

    /// Applies `--duration` (or the device default) by capping the samples delivered.
    private static func limited(
        _ source: any AudioSource,
        options: CLIOptions,
        selection: InputSelection
    ) -> any AudioSource {
        let isDevice = if case .device = selection { true } else { false }
        let duration = options.duration ?? ((isDevice && !options.continuous) ? defaultDeviceDuration : nil)
        guard let duration else { return source }
        let samples = max(1, Int((duration * Double(options.sampleRate)).rounded()))
        return DurationLimitedSource(base: source, sampleLimit: samples)
    }

    /// Maps an error from the pipeline or its source onto the CLI's failure categories.
    private static func failure(for error: Error, selection: InputSelection) -> CLIFailure {
        switch error {
        case let failure as CLIFailure:
            return failure
        case let sourceError as AudioSourceError:
            // Thrown by `start` itself: a file source that cannot open or decode its file.
            if case .file(let path, _) = selection {
                return .unreadableInput("cannot decode input file '\(path)': \(sourceError)")
            }
            return .runtime("audio input failed: \(sourceError)")
        case let pipelineError as PipelineError:
            if case .file(let path, _) = selection,
               case .audioSourceFailed(let sourceError, _) = pipelineError,
               case .formatUnsupported = sourceError {
                return .unreadableInput("cannot decode input file '\(path)': \(sourceError)")
            }
            return .runtime("analysis failed: \(pipelineError)")
        default:
            return .runtime("analysis failed: \(error.localizedDescription)")
        }
    }

    private static func write(_ text: String, to output: ResultWriter) throws(CLIFailure) {
        do {
            try output.write(line: text)
        } catch {
            throw .runtime("cannot write to stdout: \(error.localizedDescription)")
        }
    }

    private static func write(_ lines: [String], to output: ResultWriter) throws(CLIFailure) {
        for line in lines {
            try write(line, to: output)
        }
    }
}
