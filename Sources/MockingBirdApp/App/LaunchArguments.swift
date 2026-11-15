import Foundation

/// Reads the app's command line. `open MockingBird.app --args song.wav` analyses
/// `song.wav` at launch, which also gives scripted smoke tests a way in.
enum LaunchArguments {
    /// The first argument after the executable, if it names an existing regular file.
    /// Flags the system or Xcode may add (`-psn_…`, `-NSSomething YES`) are never files.
    static func fileToAnalyze(in arguments: [String]) -> URL? {
        guard let candidate = arguments.dropFirst().first, !candidate.hasPrefix("-") else {
            return nil
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidate, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return nil
        }
        return URL(fileURLWithPath: candidate)
    }
}
