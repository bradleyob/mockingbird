/// How a spawned `mockingbird` gets its standard input.
enum StandardInputMode: Sendable {
    /// A pipe the server writes PCM into, then closes.
    case pipe
    /// `/dev/null`: the CLI reads a file argument instead.
    case none
}
