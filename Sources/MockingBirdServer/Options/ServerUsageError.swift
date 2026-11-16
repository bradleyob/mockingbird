/// A command-line usage error. The process prints `message` to stderr and exits 2.
struct ServerUsageError: Error, Equatable, Codable, Sendable, CustomStringConvertible {
    let message: String

    var description: String { message }
}
