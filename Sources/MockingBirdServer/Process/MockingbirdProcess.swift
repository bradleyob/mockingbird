import Foundation

/// One running `mockingbird` subprocess: stdin writes, stdout as lines, stderr collected,
/// and its exit.
///
/// `FileHandle.readabilityHandler` and `Process.terminationHandler` callbacks are bridged into
/// `AsyncStream`s, so no `DispatchQueue` or `Thread` is used here and nothing blocks waiting
/// for output. Output is buffered eagerly, so a child can never stall on a full stdout or
/// stderr pipe while the server is busy elsewhere.
///
/// `@unchecked Sendable`: `Process` and `FileHandle` are not annotated, but every mutable
/// piece of state lives in them or in the streams, which are thread-safe.
final class MockingbirdProcess: @unchecked Sendable {
    /// Bytes per `write(2)` when piping a large body; matches the usual pipe buffer size.
    static let writeChunkSize = 65_536

    private let process: Process
    private let standardInput: FileHandle?
    private let exitTask: Task<ProcessExit, Never>

    /// The CLI's stdout, one element per line. Iterate it once.
    let standardOutputLines: DataLineSequence

    private init(
        process: Process,
        standardInput: FileHandle?,
        standardOutput: AsyncStream<Data>,
        exitTask: Task<ProcessExit, Never>
    ) {
        self.process = process
        self.standardInput = standardInput
        self.standardOutputLines = DataLineSequence(base: standardOutput)
        self.exitTask = exitTask
    }

    /// Starts `executable` with `arguments` (argv, never through a shell).
    /// - Throws: `APIError.spawnFailed` if the executable cannot be started.
    static func launch(
        executable: URL,
        arguments: [String],
        standardInput mode: StandardInputMode
    ) throws(APIError) -> MockingbirdProcess {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        let inputPipe: Pipe?
        switch mode {
        case .pipe:
            let pipe = Pipe()
            process.standardInput = pipe
            inputPipe = pipe
        case .none:
            process.standardInput = FileHandle.nullDevice
            inputPipe = nil
        }
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let standardOutput = stream(from: outputPipe.fileHandleForReading)
        let standardError = stream(from: errorPipe.fileHandleForReading)
        let (termination, terminationContinuation) = AsyncStream<ProcessExit>.makeStream()
        process.terminationHandler = { finished in
            terminationContinuation.yield(ProcessExit(
                status: finished.terminationStatus,
                signalled: finished.terminationReason == .uncaughtSignal,
                standardError: ""
            ))
            terminationContinuation.finish()
        }

        do {
            try process.run()
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            throw APIError.spawnFailed("cannot start \(executable.path): \(error.localizedDescription)")
        }

        let exitTask = Task {
            var errorBytes = Data()
            for await chunk in standardError {
                errorBytes.append(chunk)
            }
            var exit = ProcessExit(status: -1, signalled: true, standardError: "")
            for await finished in termination {
                exit = finished
            }
            return ProcessExit(
                status: exit.status,
                signalled: exit.signalled,
                standardError: String(decoding: errorBytes, as: UTF8.self)
            )
        }
        return MockingbirdProcess(
            process: process,
            standardInput: inputPipe?.fileHandleForWriting,
            standardOutput: standardOutput,
            exitTask: exitTask
        )
    }

    /// Writes `data` to the child's stdin in pipe-sized pieces.
    /// - Throws: if stdin is not a pipe, or the child has closed it (`EPIPE`; `SIGPIPE` is
    ///   ignored by `SignalDisposition`).
    func write(_ data: Data) throws {
        guard let standardInput else {
            throw APIError.analysisFailed("mockingbird stdin is not a pipe")
        }
        var offset = data.startIndex
        while offset < data.endIndex {
            let end = min(offset + Self.writeChunkSize, data.endIndex)
            try standardInput.write(contentsOf: data[offset..<end])
            offset = end
        }
    }

    /// Closes the child's stdin so it sees end of input.
    func closeStandardInput() throws {
        try standardInput?.close()
    }

    /// Sends `SIGTERM` if the child is still running.
    func terminate() {
        if process.isRunning {
            process.terminate()
        }
    }

    /// Waits until the child has exited and its stderr is drained. May be awaited repeatedly.
    func exit() async -> ProcessExit {
        await exitTask.value
    }

    private static func stream(from handle: FileHandle) -> AsyncStream<Data> {
        let (stream, continuation) = AsyncStream<Data>.makeStream()
        handle.readabilityHandler = { readable in
            let chunk = readable.availableData
            if chunk.isEmpty {
                readable.readabilityHandler = nil
                continuation.finish()
            } else {
                continuation.yield(chunk)
            }
        }
        return stream
    }
}
