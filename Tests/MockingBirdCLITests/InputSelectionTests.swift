@testable import MockingBirdCLI
import Testing

@Suite struct InputSelectionTests {
    private func select(_ options: CLIOptions, stdinIsTerminal: Bool) -> InputSelection {
        InputSelection(options: options, stdinIsTerminal: stdinIsTerminal)
    }

    @Test func fileWinsOverEverything() {
        let options = CLIOptions(device: "Mic", file: "a.wav")
        #expect(select(options, stdinIsTerminal: false) == .file(path: "a.wav", kind: .decoded))
    }

    @Test func deviceWinsOverStdin() {
        #expect(select(CLIOptions(device: "Mic"), stdinIsTerminal: false) == .device(name: "Mic"))
    }

    @Test func defaultDeviceNameMeansSystemDefault() {
        #expect(select(CLIOptions(device: "default"), stdinIsTerminal: false) == .device(name: nil))
    }

    @Test func pipedStdin() {
        #expect(select(CLIOptions(), stdinIsTerminal: false) == .standardInput)
    }

    @Test func terminalStdinFallsBackToDefaultDevice() {
        #expect(select(CLIOptions(), stdinIsTerminal: true) == .device(name: nil))
    }

    @Test(arguments: ["a.raw", "a.PCM", "dir/a.f32"])
    func rawExtensions(path: String) {
        #expect(select(CLIOptions(file: path), stdinIsTerminal: true) == .file(path: path, kind: .rawFloat32))
    }

    @Test(arguments: ["a.wav", "a.aiff", "a.m4a", "a.mp3", "noextension"])
    func decodedExtensions(path: String) {
        #expect(select(CLIOptions(file: path), stdinIsTerminal: true) == .file(path: path, kind: .decoded))
    }
}
