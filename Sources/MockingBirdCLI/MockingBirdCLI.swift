import Foundation

/// Entry point for the `mockingbird` DSP CLI.
///
/// Reads PCM (file, device or stdin), writes KeyResult lines to stdout. No HTTP.
/// Run `mockingbird --help` for the flag set.
@main
struct MockingBirdCLI {
    static func main() async {
        let status = await CLIApplication.run(
            arguments: Array(CommandLine.arguments.dropFirst()),
            stdinIsTerminal: isatty(STDIN_FILENO) != 0
        )
        exit(status.rawValue)
    }
}
