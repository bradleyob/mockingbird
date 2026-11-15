/// Where `mockingbird` reads audio from, after applying the input precedence rule.
enum InputSelection: Equatable, Sendable {
    /// How a file's bytes are interpreted.
    enum FileKind: Equatable, Sendable {
        /// Headerless mono Float32 little-endian at `--sample-rate` (`.raw`, `.pcm`, `.f32`).
        case rawFloat32
        /// A container format decoded by the platform (WAV, AIFF, M4A, ...).
        case decoded
    }

    /// An audio file.
    case file(path: String, kind: FileKind)
    /// A capture device; `nil` is the system default input.
    case device(name: String?)
    /// Raw mono Float32 little-endian PCM piped to stdin.
    case standardInput
}
