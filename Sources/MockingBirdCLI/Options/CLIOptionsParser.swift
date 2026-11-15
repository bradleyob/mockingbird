/// Turns `mockingbird`'s arguments into `CLIOptions`.
///
/// Hand-rolled on purpose: the flag set is small and fixed, and the CLI must validate
/// every value itself before building an `AudioConfig` (whose preconditions trap).
/// Accepts `--flag value` and `--flag=value`.
enum CLIOptionsParser {
    /// Parses `arguments` (without the program name).
    ///
    /// - Throws: `CLIUsageError` naming the offending flag or argument.
    static func parse(_ arguments: [String]) throws(CLIUsageError) -> CLIOptions {
        var options = CLIOptions()
        var positional: String?
        var index = arguments.startIndex

        while index < arguments.endIndex {
            let argument = arguments[index]
            index += 1

            guard isFlag(argument) else {
                if let first = positional ?? options.file {
                    throw CLIUsageError("unexpected argument '\(argument)': input file '\(first)' already given")
                }
                positional = argument
                continue
            }

            let (name, inlineValue) = split(argument)

            func value() throws(CLIUsageError) -> String {
                if let inlineValue { return inlineValue }
                guard index < arguments.endIndex, !arguments[index].hasPrefix("--") else {
                    throw CLIUsageError("missing value for \(name)")
                }
                defer { index += 1 }
                return arguments[index]
            }

            func noValue() throws(CLIUsageError) {
                if inlineValue != nil {
                    throw CLIUsageError("\(name) does not take a value")
                }
            }

            switch name {
            case "--sample-rate":
                options.sampleRate = try positiveInt(try value(), flag: name)
            case "--window-size":
                options.windowSize = try positiveInt(try value(), flag: name)
            case "--hop-size":
                options.hopSize = try positiveInt(try value(), flag: name)
            case "--alternates":
                options.alternates = try int(try value(), flag: name)
                guard options.alternates >= 0 else {
                    throw CLIUsageError("\(name) must be 0 or more, got \(options.alternates)")
                }
            case "--zero-pad":
                try noValue()
                options.zeroPad = true
            case "--profiles":
                options.profilesPath = try nonEmpty(try value(), flag: name)
            case "--device":
                options.device = try nonEmpty(try value(), flag: name)
            case "--continuous":
                try noValue()
                options.continuous = true
            case "--format":
                let raw = try value()
                guard let format = OutputFormat(rawValue: raw) else {
                    let allowed = OutputFormat.allCases.map(\.rawValue).joined(separator: "|")
                    throw CLIUsageError("invalid value '\(raw)' for --format: expected \(allowed)")
                }
                options.format = format
            case "--duration":
                let raw = try value()
                guard let seconds = Double(raw), seconds.isFinite else {
                    throw CLIUsageError("invalid value '\(raw)' for --duration: expected seconds")
                }
                guard seconds > 0 else {
                    throw CLIUsageError("--duration must be greater than 0, got \(raw)")
                }
                options.duration = seconds
            case "--list-devices":
                try noValue()
                options.listDevices = true
            case "--file":
                let path = try nonEmpty(try value(), flag: name)
                if let first = positional ?? options.file {
                    throw CLIUsageError("--file '\(path)': input file '\(first)' already given")
                }
                options.file = path
            case "--help", "-h":
                try noValue()
                options.showHelp = true
            case "--version":
                try noValue()
                options.showVersion = true
            default:
                throw CLIUsageError("unknown option '\(name)'")
            }
        }

        if let positional {
            options.file = positional
        }
        try validate(options)
        return options
    }

    // MARK: - Private

    /// Cross-flag checks, run once every flag has been read so flag order does not matter.
    private static func validate(_ options: CLIOptions) throws(CLIUsageError) {
        let window = options.windowSize
        guard window >= 2, window & (window - 1) == 0 else {
            throw CLIUsageError("--window-size must be a power of two, got \(window)")
        }
        guard options.hopSize <= window else {
            throw CLIUsageError("--hop-size must be between 1 and the window size (\(window)), got \(options.hopSize)")
        }
    }

    /// A token is a flag if it starts with `-` and is not a negative number
    /// (so `--alternates -1` reports a range error, not a missing value).
    private static func isFlag(_ argument: String) -> Bool {
        argument.count > 1 && argument.hasPrefix("-") && Double(argument) == nil
    }

    private static func split(_ argument: String) -> (name: String, value: String?) {
        guard argument.hasPrefix("--"), let equals = argument.firstIndex(of: "=") else {
            return (argument, nil)
        }
        return (String(argument[..<equals]), String(argument[argument.index(after: equals)...]))
    }

    private static func int(_ raw: String, flag: String) throws(CLIUsageError) -> Int {
        guard let value = Int(raw) else {
            throw CLIUsageError("invalid value '\(raw)' for \(flag): expected an integer")
        }
        return value
    }

    private static func positiveInt(_ raw: String, flag: String) throws(CLIUsageError) -> Int {
        let value = try int(raw, flag: flag)
        guard value > 0 else {
            throw CLIUsageError("\(flag) must be greater than 0, got \(value)")
        }
        return value
    }

    private static func nonEmpty(_ raw: String, flag: String) throws(CLIUsageError) -> String {
        guard !raw.isEmpty else {
            throw CLIUsageError("\(flag) must not be empty")
        }
        return raw
    }
}
