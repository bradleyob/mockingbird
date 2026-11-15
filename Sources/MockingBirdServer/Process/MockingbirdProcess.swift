import Foundation
import NIOCore
import NIOPosix

/// One running `mockingbird` subprocess: stdin writes, stdout as lines, stderr collected,
/// and its exit.
///
/// The parent ends of the stdio pipes are SwiftNIO pipe channels, so reads and writes are
/// non-blocking and never tie up a Swift concurrency thread, and stdin writes get
/// back-pressure from the event loop. `FileHandle.readabilityHandler` is not used: on Linux,
/// swift-corelibs-foundation sometimes never reports end of file through it, which hung
/// requests. Output is read eagerly into `AsyncStream`s, so a child can never stall on a full
/// stdout or stderr pipe. `Process.terminationHandler` is bridged into an `AsyncStream` too;
/// no `DispatchQueue` or `Thread` is used.
///
/// `@unchecked Sendable`: `Process` is not annotated; it is only used for `run`,
/// `isRunning` and `processIdentifier`, which are safe from any thread.
final class MockingbirdProcess: @unchecked Sendable {
    /// How long to keep draining stderr after the process has exited.
    static let stderrGrace = Duration.seconds(1)

    private let process: Process
    private let standardInput: (any Channel)?
    private let exitTask: Task<ProcessExit, Never>

    /// The CLI's stdout, one element per line. Iterate it once.
    let standardOutputLines: DataLineSequence

    private init(
        process: Process,
        standardInput: (any Channel)?,
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
    ) async throws(APIError) -> MockingbirdProcess {
        SignalDisposition.ignoreBrokenPipe()
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        let inputPipe: PipeDescriptors?
        let outputPipe: PipeDescriptors
        let errorPipe: PipeDescriptors
        do {
            inputPipe = mode == .pipe ? try PipeDescriptors() : nil
            outputPipe = try PipeDescriptors()
            errorPipe = try PipeDescriptors()
        } catch {
            throw APIError.spawnFailed("cannot create pipes: \(error)")
        }
        // The child's ends, closed in the parent once the child has them.
        var childEnds: [FileHandle] = []
        if let inputPipe {
            childEnds.append(FileHandle(fileDescriptor: inputPipe.read, closeOnDealloc: true))
        } else if let devNull = FileHandle(forReadingAtPath: "/dev/null") {
            childEnds.append(devNull)
        } else {
            throw APIError.spawnFailed("cannot open /dev/null")
        }
        childEnds.append(FileHandle(fileDescriptor: outputPipe.write, closeOnDealloc: true))
        childEnds.append(FileHandle(fileDescriptor: errorPipe.write, closeOnDealloc: true))
        process.standardInput = childEnds[0]
        process.standardOutput = childEnds[1]
        process.standardError = childEnds[2]

        let (termination, terminationContinuation) = AsyncStream<ProcessExit>.makeStream()
        process.terminationHandler = { finished in
            terminationContinuation.yield(ProcessExit(
                status: finished.terminationStatus,
                signalled: finished.terminationReason == .uncaughtSignal,
                standardError: ""
            ))
            terminationContinuation.finish()
        }

        let parentEnds = [inputPipe?.write, outputPipe.read, errorPipe.read].compactMap { $0 }
        do {
            try process.run()
        } catch {
            closeQuietly(childEnds)
            parentEnds.forEach { PipeDescriptors.close($0) }
            throw APIError.spawnFailed("cannot start \(executable.path): \(error.localizedDescription)")
        }
        closeQuietly(childEnds)

        let standardOutput: AsyncStream<Data>
        let standardError: AsyncStream<Data>
        let standardInput: (any Channel)?
        do {
            standardOutput = try await readStream(outputPipe.read)
            standardError = try await readStream(errorPipe.read)
            if let inputPipe {
                standardInput = try await NIOPipeBootstrap(group: MultiThreadedEventLoopGroup.singleton)
                    .takingOwnershipOfDescriptor(output: inputPipe.write) { channel in
                        channel.eventLoop.makeSucceededFuture(channel)
                    }
            } else {
                standardInput = nil
            }
        } catch {
            _ = kill(process.processIdentifier, SIGKILL)
            throw APIError.spawnFailed("cannot attach to mockingbird's pipes: \(error)")
        }

        let errorTask = Task {
            var errorBytes = Data()
            for await chunk in standardError {
                errorBytes.append(chunk)
            }
            return errorBytes
        }
        let pid = process.processIdentifier
        let exitTask = Task {
            let exit = await withTaskGroup(of: ProcessExit?.self) { group in
                group.addTask {
                    for await finished in termination {
                        return finished
                    }
                    return nil
                }
                group.addTask { await ZombieProbe.waitForExit(of: pid) }
                var first: ProcessExit?
                while first == nil, let next = await group.next() {
                    first = next
                }
                group.cancelAll()
                return first ?? ProcessExit(status: -1, signalled: true, standardError: "")
            }
            // A grandchild that inherited stderr can hold it open after the CLI exits; give
            // the drain a moment, then report what arrived rather than hold the pool slot.
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    _ = await errorTask.value
                }
                group.addTask {
                    do {
                        try await Task.sleep(for: Self.stderrGrace)
                    } catch {
                        return
                    }
                    // errorTask is unstructured, so group cancellation would not reach it.
                    errorTask.cancel()
                }
                _ = await group.next()
                group.cancelAll()
            }
            return ProcessExit(
                status: exit.status,
                signalled: exit.signalled,
                standardError: String(decoding: await errorTask.value, as: UTF8.self)
            )
        }
        return MockingbirdProcess(
            process: process,
            standardInput: standardInput,
            standardOutput: standardOutput,
            exitTask: exitTask
        )
    }

    /// Writes `data` to the child's stdin, returning once the event loop has written it all.
    /// - Throws: if stdin is not a pipe or the child has closed it (`EPIPE`).
    func write(_ data: Data) async throws {
        guard let standardInput else {
            throw APIError.analysisFailed("mockingbird stdin is not a pipe")
        }
        try await standardInput.writeAndFlush(ByteBuffer(bytes: data)).get()
    }

    /// Closes the child's stdin so it sees end of input.
    func closeStandardInput() async throws {
        try await standardInput?.close()
    }

    /// Kills the child if it is still running, and closes its stdin so anything it left
    /// behind reading stdin sees end of input too.
    ///
    /// `SIGKILL`, not `Process.terminate()` (`SIGTERM`): on Linux, swift-corelibs-foundation
    /// spawns children with the spawning thread's signal mask, and Swift concurrency threads
    /// block `SIGTERM`, so a terminated CLI would never die. The CLI holds nothing that
    /// needs a graceful shutdown.
    func terminate() {
        if process.isRunning {
            _ = kill(process.processIdentifier, SIGKILL)
        }
        standardInput?.close(promise: nil)
    }

    /// Waits until the child has exited and its stderr is drained. May be awaited repeatedly.
    func exit() async -> ProcessExit {
        await exitTask.value
    }

    /// Reads a pipe on the event loop into a stream that finishes at end of file.
    private static func readStream(_ descriptor: CInt) async throws -> AsyncStream<Data> {
        let (stream, continuation) = AsyncStream<Data>.makeStream()
        do {
            _ = try await NIOPipeBootstrap(group: MultiThreadedEventLoopGroup.singleton)
                .takingOwnershipOfDescriptor(input: descriptor) { channel in
                    channel.eventLoop.makeCompletedFuture {
                        try channel.pipeline.syncOperations.addHandler(PipeReadHandler(continuation: continuation))
                    }
                }
        } catch {
            continuation.finish()
            throw error
        }
        return stream
    }

    private static func closeQuietly(_ handles: [FileHandle]) {
        for handle in handles {
            do {
                try handle.close()
            } catch {
                // Already closed; nothing to release.
            }
        }
    }
}

extension MockingbirdProcess {
    /// Writes all of `data` to stdin, then closes it. A write failure means the child closed
    /// its stdin early (usually because it has already failed); that is not an error here —
    /// the child's exit status says what went wrong.
    func sendInput(_ data: Data) async {
        do {
            try await write(data)
        } catch {
            // Reported through the exit status instead.
        }
        do {
            try await closeStandardInput()
        } catch {
            // Already closed: nothing left to signal.
        }
    }
}
