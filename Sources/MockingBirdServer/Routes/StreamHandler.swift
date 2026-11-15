import Foundation
import Hummingbird
import HummingbirdWebSocket

/// `WS /stream` (contract §4.4): binary frames of mono Float32 LE PCM in, one text frame per
/// CLI result line out.
///
/// - The socket is upgraded at once; frames are not read until the connection holds a pool
///   slot, so a queued client simply sees back-pressure.
/// - Text frame `end`: stdin is closed, remaining lines are forwarded, then a normal close.
/// - Client gone without `end`: the subprocess is terminated.
/// - Failure: one text frame with the error object, then close code 1011.
struct StreamHandler: Sendable {
    /// Largest binary message accepted, in bytes.
    static let maxMessageSize = 1 << 20
    /// The text frame that ends the input.
    static let endMessage = "end"

    let options: ServerOptions
    let pool: ProcessPool

    func handle(inbound: WebSocketInboundStream, outbound: WebSocketOutboundWriter, request: Request) async throws {
        let failure: APIError?
        do {
            let parameters = try AnalysisParametersParser.parse(request.uri.queryPairs)
            failure = try await pool.run(
                executable: options.mockingbird,
                arguments: CLIArguments.stream(parameters),
                standardInput: .pipe
            ) { process in
                try await pump(process: process, inbound: inbound, outbound: outbound)
            }
        } catch let error as APIError {
            failure = error
        }
        if let failure {
            try await outbound.write(.text(failure.json))
            // Throwing makes the WebSocket layer close with 1011 (unexpected server error).
            throw failure
        }
    }

    /// Moves audio in and results out until the client sends `end` or goes away.
    /// - Returns: the error to report, or `nil` for a normal close.
    private func pump(
        process: MockingbirdProcess,
        inbound: WebSocketInboundStream,
        outbound: WebSocketOutboundWriter
    ) async throws -> APIError? {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for await line in process.standardOutputLines {
                    try await outbound.write(.text(line))
                }
            }

            let inputEnded = await forwardInput(from: inbound, to: process)
            guard inputEnded else {
                process.terminate()
                group.cancelAll()
                return nil
            }
            do {
                try process.closeStandardInput()
            } catch {
                // The CLI already closed it; its exit status explains why.
            }
            try await group.waitForAll()
            return ProcessExitClassifier.error(for: await process.exit())
        }
    }

    /// Writes binary messages to stdin.
    /// - Returns: `true` when input ended on purpose (`end`, or the CLI stopped reading),
    ///   `false` when the client disconnected.
    private func forwardInput(from inbound: WebSocketInboundStream, to process: MockingbirdProcess) async -> Bool {
        do {
            for try await message in inbound.messages(maxSize: Self.maxMessageSize) {
                switch message {
                case .binary(let buffer):
                    do {
                        try process.write(Data(buffer: buffer))
                    } catch {
                        return true
                    }
                case .text(let text):
                    if text == Self.endMessage {
                        return true
                    }
                }
            }
        } catch {
            return false
        }
        return false
    }
}
