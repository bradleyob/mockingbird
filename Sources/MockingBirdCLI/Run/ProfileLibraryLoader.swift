import Foundation
import MockingBirdCore

/// Loads a `--profiles` JSON file as a `ProfileLibrary`.
enum ProfileLibraryLoader {
    /// - Throws: `CLIFailure.unreadableInput` if the file cannot be read, is not a valid
    ///   library, has no profiles, or has a profile without exactly 12 weights.
    static func load(path: String) throws(CLIFailure) -> ProfileLibrary {
        let library: ProfileLibrary
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            library = try JSONDecoder().decode(ProfileLibrary.self, from: data)
        } catch {
            throw .unreadableInput("cannot load profiles '\(path)': \(describe(error))")
        }
        // Checked here as well as in Core's decoder so a bad file can never reach a
        // KeyDetector precondition, whichever Core version this links.
        guard !library.profiles.isEmpty else {
            throw .unreadableInput("cannot load profiles '\(path)': library has no profiles")
        }
        if let bad = library.profiles.first(where: { $0.weights.count != 12 }) {
            throw .unreadableInput(
                "cannot load profiles '\(path)': profile '\(bad.name)' has \(bad.weights.count) weights, expected 12"
            )
        }
        return library
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case DecodingError.dataCorrupted(let context),
             DecodingError.keyNotFound(_, let context),
             DecodingError.typeMismatch(_, let context),
             DecodingError.valueNotFound(_, let context):
            return context.debugDescription
        default:
            return error.localizedDescription
        }
    }
}
