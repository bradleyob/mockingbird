/// What the command line asked the server process to do.
enum ServerCommand: Equatable, Sendable {
    /// Serve with these options.
    case run(ServerOptions)
    /// Print usage to stdout and exit 0.
    case help
}
