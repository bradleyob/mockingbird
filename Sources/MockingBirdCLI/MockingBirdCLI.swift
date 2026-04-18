import Foundation
import MockingBirdCore
#if canImport(AVFoundation)
import AudioSourceAVFoundation
#elseif os(Linux)
import AudioSourceMiniAudio
#endif

// MARK: - Entry point for the `mockingbird` DSP CLI binary.
//
// Reads PCM (stdin / file / device), writes KeyResult JSON to stdout. No HTTP.
//
// Usage:
//   mockingbird                           # live mic
//   mockingbird --file path/to/audio.raw  # from file
//   cat audio.raw | mockingbird           # stdin pipe

@main
struct MockingBirdCLI {
    static func main() async {
        let args = CommandLine.arguments

        do {
            let source: any AudioSource
            if let fileIndex = args.firstIndex(of: "--file"), fileIndex + 1 < args.count {
                let path = args[fileIndex + 1]
                source = FileSource(url: URL(fileURLWithPath: path))
            } else if isStdinPipe() {
                source = RawPCMSource(handle: .standardInput)
            } else {
                #if canImport(AVFoundation)
                source = AVFoundationSource()
                #elseif os(Linux)
                source = MiniAudioSource()
                #else
                fputs("error: no audio source available on this platform\n", stderr)
                exit(1)
                #endif
            }

            let config = AudioConfig()
            let pipeline = try AnalysisPipeline(source: source, config: config)
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys

            for try await result in try await pipeline.start() {
                let json = try encoder.encode(result)
                print(String(decoding: json, as: UTF8.self))
                fflush(stdout)
            }
        } catch let error as PipelineError {
            fputs("error: \(error)\n", stderr)
            exit(1)
        } catch {
            fputs("error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func isStdinPipe() -> Bool {
        isatty(STDIN_FILENO) == 0
    }
}
