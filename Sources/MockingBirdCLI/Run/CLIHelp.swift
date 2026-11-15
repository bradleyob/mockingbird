/// Static text printed by `--help` and `--version`.
enum CLIHelp {
    /// Reported by `--version`.
    static let version = "mockingbird 0.2.0"

    /// Reported by `--help`.
    static let usage = """
    USAGE: mockingbird [options] [<file>]

    Detects the musical key of audio and writes KeyResult JSON lines to stdout.

    INPUT (first that applies):
      <file>, --file <path>   .raw/.pcm/.f32: mono Float32 LE at --sample-rate;
                              anything else (wav, aiff, m4a, ...) is decoded
      --device <name>         capture device by name; "default" = system default input
      stdin                   mono Float32 LE at --sample-rate, when stdin is not a terminal
      default device          when stdin is a terminal

    OPTIONS:
      --sample-rate <int>     raw input rate and analysis rate (default 44100)
      --window-size <int>     FFT window, power of two (default 4096)
      --hop-size <int>        samples between windows, 1...window-size (default 2048)
      --alternates <int>      alternate keys per result, >= 0 (default 3)
      --zero-pad              zero-pad each window to twice its length
      --profiles <path>       ProfileLibrary JSON replacing the built-in profiles
      --continuous            one rolling (~15 s) result per hop instead of one at the end
      --format json|line      output format (default json)
      --duration <seconds>    stop after this much audio (default: end of input;
                              10 for device input without --continuous)
      --list-devices          print capture device names, one per line
      --help                  show this help
      --version               show the version

    EXIT STATUS:
      0 ok, 1 runtime failure, 2 usage error, 3 input shorter than one window,
      4 input or profiles file unreadable
    """
}
