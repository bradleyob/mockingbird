import Foundation
import Hummingbird

/// `POST /analyze`: one audio body in, the CLI's single KeyResult line out (contract §4.4).
struct AnalyzeHandler: Sendable {
    let options: ServerOptions
    let pool: ProcessPool

    func handle(_ request: Request) async -> Response {
        do {
            let line = try await analyze(request)
            return Response(
                status: .ok,
                headers: [.contentType: "application/json"],
                body: ResponseBody(byteBuffer: ByteBuffer(string: line + "\n"))
            )
        } catch let error as APIError {
            return error.response
        } catch {
            return APIError.analysisFailed("\(error)").response
        }
    }

    private func analyze(_ request: Request) async throws -> String {
        let parameters = try AnalysisParametersParser.parse(request.uri.queryPairs)
        let mediaType = try AudioMediaTypeResolver.resolve(request.headers[.contentType])
        let body = try await collectBody(request)
        guard !body.isEmpty else {
            throw APIError.emptyBody()
        }
        switch mediaType {
        case .rawPCM:
            return try await run(arguments: CLIArguments.analyze(parameters), standardInput: .pipe, input: body)
        case .encoded(let fileExtension):
            let file = options.temporaryDirectory
                .appendingPathComponent("mockingbird-upload-\(UUID().uuidString)")
                .appendingPathExtension(fileExtension)
            do {
                try body.write(to: file)
            } catch {
                throw APIError.analysisFailed("cannot stage upload: \(error.localizedDescription)")
            }
            let result: Result<String, any Error>
            do {
                result = .success(try await run(
                    arguments: CLIArguments.analyze(parameters, file: file.path), standardInput: .none, input: nil))
            } catch {
                result = .failure(error)
            }
            removeStagedFile(file)
            return try result.get()
        }
    }

    /// Reads the body, refusing anything over `maxBodyBytes` without buffering it all.
    private func collectBody(_ request: Request) async throws -> Data {
        let limit = options.maxBodyBytes
        if let declared = request.headers[.contentLength].flatMap(Int.init), declared > limit {
            throw APIError.payloadTooLarge(limit: limit)
        }
        var collected = ByteBuffer()
        for try await chunk in request.body {
            guard collected.readableBytes + chunk.readableBytes <= limit else {
                throw APIError.payloadTooLarge(limit: limit)
            }
            collected.writeImmutableBuffer(chunk)
        }
        return Data(collected.readableBytesView)
    }

    /// Spawns the CLI in a pool slot, feeds `input` to stdin while reading stdout, and returns
    /// the last stdout line.
    private func run(arguments: [String], standardInput: StandardInputMode, input: Data?) async throws -> String {
        try await pool.run(executable: options.mockingbird, arguments: arguments, standardInput: standardInput) { process in
            try await withTaskGroup(of: Void.self) { group in
                if let input {
                    group.addTask { process.sendInput(input) }
                }
                var lastLine: String?
                for await line in process.standardOutputLines {
                    lastLine = line
                }
                await group.waitForAll()
                let exit = await process.exit()
                return Result { () throws(APIError) -> String in
                    try ProcessExitClassifier.keyResultLine(exit: exit, lastLine: lastLine)
                }
            }.get()
        }
    }

    private func removeStagedFile(_ file: URL) {
        do {
            try FileManager.default.removeItem(at: file)
        } catch {
            // Nothing more can be done; the OS cleans its temp directory eventually.
        }
    }
}
