extension InputSelection {
    /// File extensions read as headerless Float32 PCM rather than decoded.
    static let rawExtensions: Set<String> = ["raw", "pcm", "f32"]

    /// Applies the CLI's input precedence:
    /// file > `--device` > stdin when it is not a terminal > default device.
    ///
    /// - Parameter stdinIsTerminal: whether stdin is attached to a TTY.
    init(options: CLIOptions, stdinIsTerminal: Bool) {
        if let path = options.file {
            self = .file(path: path, kind: Self.kind(ofPath: path))
        } else if let device = options.device {
            self = .device(name: device == "default" ? nil : device)
        } else if !stdinIsTerminal {
            self = .standardInput
        } else {
            self = .device(name: nil)
        }
    }

    private static func kind(ofPath path: String) -> FileKind {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return .decoded }
        let fileExtension = name[name.index(after: dot)...].lowercased()
        return rawExtensions.contains(fileExtension) ? .rawFloat32 : .decoded
    }
}
