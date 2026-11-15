/// Builds `mockingbird` argv (contract §4.3) from validated parameters. Arguments are passed
/// to the process directly, never through a shell.
enum CLIArguments {
    /// One cumulative result for the whole input; `file` is the positional input, if any.
    static func analyze(_ parameters: AnalysisParameters, file: String? = nil) -> [String] {
        options(parameters) + ["--format", "json"] + (file.map { [$0] } ?? [])
    }

    /// One rolling result per hop, for `WS /stream`.
    static func stream(_ parameters: AnalysisParameters) -> [String] {
        options(parameters) + ["--continuous", "--format", "json"]
    }

    private static func options(_ parameters: AnalysisParameters) -> [String] {
        var arguments: [String] = []
        if let sampleRate = parameters.sampleRate {
            arguments += ["--sample-rate", String(sampleRate)]
        }
        if let windowSize = parameters.windowSize {
            arguments += ["--window-size", String(windowSize)]
        }
        if let hopSize = parameters.hopSize {
            arguments += ["--hop-size", String(hopSize)]
        }
        if let alternates = parameters.alternates {
            arguments += ["--alternates", String(alternates)]
        }
        if parameters.zeroPad {
            arguments.append("--zero-pad")
        }
        return arguments
    }
}
