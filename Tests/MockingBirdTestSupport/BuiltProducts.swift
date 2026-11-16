import Foundation

/// Locates executables built by this package (`mockingbird`, `mockingbird-server`) so
/// integration tests can run the real binaries.
///
/// A test target must list the executable's target as a dependency so SwiftPM builds it
/// before the tests run.
public enum BuiltProducts {
    public struct NotFound: Error, CustomStringConvertible {
        public let name: String
        public let searched: [String]
        public var description: String {
            "built product '\(name)' not found; searched: \(searched.joined(separator: ", "))"
        }
    }

    /// URL of the built executable `name`. Set `MOCKINGBIRD_BIN_DIR` to override the search.
    public static func executable(_ name: String) throws -> URL {
        let candidates = candidateDirectories()
        for directory in candidates {
            let url = directory.appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }
        throw NotFound(name: name, searched: candidates.map(\.path))
    }

    private static func candidateDirectories() -> [URL] {
        var directories: [URL] = []
        if let override = ProcessInfo.processInfo.environment["MOCKINGBIRD_BIN_DIR"] {
            directories.append(URL(fileURLWithPath: override))
        }
        // The image containing this code is the test bundle binary, which SwiftPM places in
        // (Linux) or a few levels below (macOS .xctest bundle) the products directory.
        #if canImport(Darwin)
        var info = Dl_info()
        if dladdr(#dsohandle, &info) != 0, let imagePath = info.dli_fname {
            var directory = URL(fileURLWithPath: String(cString: imagePath)).deletingLastPathComponent()
            for _ in 0..<5 {
                directories.append(directory)
                directory = directory.deletingLastPathComponent()
            }
        }
        #else
        // On Linux the test runner is itself an executable in the products directory.
        if let executable = Bundle.main.executableURL {
            directories.append(executable.deletingLastPathComponent())
        }
        #endif
        directories.append(Bundle.main.bundleURL)
        return directories
    }
}
