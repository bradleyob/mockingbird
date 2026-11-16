#if os(macOS)
import AudioSourceAVFoundation
import Foundation
import MockingBirdCore
import Testing

/// Device listing and lookup. Nothing here starts capture, so no microphone permission
/// prompt can appear: an unknown device must be rejected before the engine is touched.
@Suite struct DeviceSelectionTests {
    @Test func inputDeviceNamesAreNonEmptyAndUnique() {
        let names = AVFoundationSource.inputDeviceNames()
        #expect(names.allSatisfy { !$0.isEmpty })
        #expect(Set(names).count == names.count)
    }

    @Test func listDevicesPrintsTheSameNames() async throws {
        let run = try await CLIInvocation.run(["--list-devices"])
        #expect(run.status == 0)
        #expect(run.stderr.isEmpty)
        #expect(run.lines == AVFoundationSource.inputDeviceNames())
    }

    @Test func unknownDeviceFailsBeforeCapture() {
        let source = AVFoundationSource(deviceName: "no-such-device-xyz")
        #expect {
            _ = try source.start(sampleRate: 44100)
        } throws: { error in
            guard case .deviceUnavailable = error as? AudioSourceError else { return false }
            return true
        }
    }

    @Test func unknownDeviceExitsOneNamingTheDevice() async throws {
        let run = try await CLIInvocation.run(["--device", "no-such-device-xyz"])
        #expect(run.status == 1)
        #expect(run.stdout.isEmpty)
        #expect(run.stderr.hasPrefix("mockingbird: error:"))
        #expect(run.stderr.contains("no-such-device-xyz"))
    }
}
#endif
