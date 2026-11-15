/// Every setting `mockingbird` accepts on the command line, already validated.
///
/// Defaults match the `mockingbird` CLI contract and `AudioConfig()`.
struct CLIOptions: Equatable, Sendable {
    /// Rate of raw PCM input, and analysis rate for decoded or device input.
    var sampleRate = 44100
    /// FFT window size in samples; a power of two.
    var windowSize = 4096
    /// Samples between successive windows; `1...windowSize`.
    var hopSize = 2048
    /// Number of alternate candidates per result.
    var alternates = 3
    /// Zero-pad each window to twice its length before the FFT.
    var zeroPad = false
    /// Path of a `ProfileLibrary` JSON file replacing the built-in library.
    var profilesPath: String?
    /// Capture device name; `"default"` selects the system default input.
    var device: String?
    /// Emit a rolling result every hop instead of one result at the end.
    var continuous = false
    /// Output rendering.
    var format = OutputFormat.json
    /// Stop after this many seconds of audio. `nil` means the input's own end
    /// (or 10 s for device input without `--continuous`).
    var duration: Double?
    /// Print capture device names and exit.
    var listDevices = false
    /// Input file path, from the positional argument or `--file`.
    var file: String?
    /// Print usage and exit.
    var showHelp = false
    /// Print the version and exit.
    var showVersion = false
}
