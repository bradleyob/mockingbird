import Foundation

/// Parses `mockingbird-server` arguments (contract §4.4). Hand-rolled; no dependency.
enum ServerOptionsParser {
    static let usage = """
        usage: mockingbird-server [options]

          --port <int>             TCP port (default 7742)
          --host <string>          interface to bind (default 127.0.0.1)
          --max-connections <int>  concurrent mockingbird subprocesses (default 4)
          --mockingbird <path>     mockingbird CLI (default: next to this executable)
          --max-body-bytes <int>   largest POST /analyze body (default 104857600)
          --help                   show this help

        """

    /// - Parameters:
    ///   - arguments: Command-line arguments without the program name.
    ///   - serverExecutable: Location of the running server binary; the default
    ///     `--mockingbird` is the `mockingbird` file in the same directory.
    static func parse(_ arguments: [String], serverExecutable: URL) throws(ServerUsageError) -> ServerCommand {
        var host = ServerOptions.defaultHost
        var port = ServerOptions.defaultPort
        var maxConnections = ServerOptions.defaultMaxConnections
        var maxBodyBytes = ServerOptions.defaultMaxBodyBytes
        var mockingbird = serverExecutable.deletingLastPathComponent().appendingPathComponent("mockingbird")

        var remaining = arguments[...]
        while let flag = remaining.popFirst() {
            switch flag {
            case "--help", "-h":
                return .help
            case "--host":
                host = try nonEmpty(try value(for: flag, in: &remaining), flag: flag)
            case "--port":
                port = try integer(try value(for: flag, in: &remaining), flag: flag, in: 0...65535)
            case "--max-connections":
                maxConnections = try integer(try value(for: flag, in: &remaining), flag: flag, in: 1...Int.max)
            case "--max-body-bytes":
                maxBodyBytes = try integer(try value(for: flag, in: &remaining), flag: flag, in: 1...Int.max)
            case "--mockingbird":
                let path = try nonEmpty(try value(for: flag, in: &remaining), flag: flag)
                mockingbird = URL(fileURLWithPath: path)
            default:
                throw ServerUsageError(message: flag.hasPrefix("-")
                    ? "unknown option '\(flag)'"
                    : "unexpected argument '\(flag)'")
            }
        }
        return .run(ServerOptions(
            host: host,
            port: port,
            maxConnections: maxConnections,
            mockingbird: mockingbird,
            maxBodyBytes: maxBodyBytes
        ))
    }

    private static func value(for flag: String, in remaining: inout ArraySlice<String>) throws(ServerUsageError) -> String {
        guard let value = remaining.popFirst() else {
            throw ServerUsageError(message: "option '\(flag)' requires a value")
        }
        return value
    }

    private static func nonEmpty(_ value: String, flag: String) throws(ServerUsageError) -> String {
        guard !value.isEmpty else {
            throw ServerUsageError(message: "option '\(flag)' must not be empty")
        }
        return value
    }

    private static func integer(_ value: String, flag: String, in range: ClosedRange<Int>) throws(ServerUsageError) -> Int {
        guard let number = Int(value), range.contains(number) else {
            throw ServerUsageError(message: "option '\(flag)' expects an integer in \(range.lowerBound)...\(range.upperBound), got '\(value)'")
        }
        return number
    }
}
