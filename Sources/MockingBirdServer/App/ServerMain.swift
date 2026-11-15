import Foundation
import Hummingbird

/// Entry point for `mockingbird-server`, the HTTP/WebSocket gateway in front of the
/// `mockingbird` CLI. Parses options and runs the application; the routes live in
/// `ApplicationBuilder`. No DSP, no MockingBirdCore.
@main
enum ServerMain {
    static func main() async throws {
        let command: ServerCommand
        do {
            command = try ServerOptionsParser.parse(
                Array(CommandLine.arguments.dropFirst()),
                serverExecutable: currentExecutable()
            )
        } catch {
            FileHandle.standardError.write(Data("mockingbird-server: error: \(error.message)\n".utf8))
            exit(2)
        }
        switch command {
        case .help:
            FileHandle.standardOutput.write(Data(ServerOptionsParser.usage.utf8))
        case .run(let options):
            try await ApplicationBuilder(options: options).build().runService()
        }
    }

    private static func currentExecutable() -> URL {
        if let url = Bundle.main.executableURL {
            return url.resolvingSymlinksInPath()
        }
        return URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    }
}
