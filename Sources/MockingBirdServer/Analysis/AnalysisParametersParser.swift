/// Validates query parameters into `AnalysisParameters`.
///
/// Values are checked here, before anything is spawned, so that a bad value is a `400` and
/// never reaches the CLI (whose `AudioConfig` preconditions would trap). Unknown parameter
/// names are ignored; a repeated name takes its last value.
enum AnalysisParametersParser {
    /// Mirrors the CLI's own default, used to bound `hopSize` when `windowSize` is absent.
    static let defaultWindowSize = 4096
    static let maxSampleRate = 768_000
    static let maxWindowSize = 1 << 20

    static func parse(_ query: [(name: String, value: String)]) throws(APIError) -> AnalysisParameters {
        var parameters = AnalysisParameters()
        for (name, value) in query {
            switch name {
            case "sampleRate":
                parameters.sampleRate = try integer(name, value, in: 1...maxSampleRate)
            case "windowSize":
                let size = try integer(name, value, in: 2...maxWindowSize)
                guard size & (size - 1) == 0 else {
                    throw APIError.invalidParameter("windowSize must be a power of two, got \(size)")
                }
                parameters.windowSize = size
            case "hopSize":
                parameters.hopSize = try integer(name, value, in: 1...maxWindowSize)
            case "alternates":
                parameters.alternates = try integer(name, value, in: 0...Int(Int32.max))
            case "zeroPad":
                parameters.zeroPad = try boolean(name, value)
            default:
                continue
            }
        }
        let window = parameters.windowSize ?? defaultWindowSize
        if let hop = parameters.hopSize, hop > window {
            throw APIError.invalidParameter("hopSize must be at most windowSize (\(window)), got \(hop)")
        }
        return parameters
    }

    private static func integer(_ name: String, _ value: String, in range: ClosedRange<Int>) throws(APIError) -> Int {
        guard let number = Int(value), range.contains(number) else {
            throw APIError.invalidParameter(
                "\(name) must be an integer in \(range.lowerBound)...\(range.upperBound), got '\(value)'")
        }
        return number
    }

    private static func boolean(_ name: String, _ value: String) throws(APIError) -> Bool {
        switch value.lowercased() {
        case "true", "1": return true
        case "false", "0": return false
        default: throw APIError.invalidParameter("\(name) must be true or false, got '\(value)'")
        }
    }
}
