import Foundation

/// Detects a child that has exited but not yet been reaped, without reaping it.
///
/// Needed on Linux only: swift-corelibs-foundation learns that a child exited through a
/// socket the child inherits, so `terminationHandler` waits until every descendant holding
/// that socket has exited too. A CLI killed while a grandchild lives would otherwise keep its
/// pool slot. `/proc/<pid>/stat` shows the zombie and its wait status (field 52, Linux 3.5+);
/// reading it leaves reaping to Foundation.
enum ZombieProbe {
    static let pollInterval = Duration.milliseconds(50)

    /// Polls until `pid` is a zombie, then returns its exit. Returns `nil` if the platform
    /// has no `/proc`, or if the process is gone without a readable status (already reaped).
    static func waitForExit(of pid: Int32) async -> ProcessExit? {
        #if os(Linux)
        while !Task.isCancelled {
            switch read(pid) {
            case .running:
                do {
                    try await Task.sleep(for: pollInterval)
                } catch {
                    return nil
                }
            case .exited(let exit):
                return exit
            case .unknown:
                return nil
            }
        }
        return nil
        #else
        return nil
        #endif
    }

    private enum State {
        case running
        case exited(ProcessExit)
        case unknown
    }

    private static func read(_ pid: Int32) -> State {
        guard let stat = try? String(contentsOfFile: "/proc/\(pid)/stat", encoding: .utf8),
              let commandEnd = stat.lastIndex(of: ")")
        else {
            return .unknown
        }
        // Fields after "(comm)": index 0 is field 3 (state); field 52 (exit_code) is index 49.
        let fields = stat[stat.index(after: commandEnd)...].split(separator: " ")
        guard let state = fields.first else { return .unknown }
        guard state == "Z" else { return .running }
        guard fields.count > 49, let status = Int32(fields[49].trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return .unknown
        }
        let signal = status & 0x7F
        return .exited(ProcessExit(
            status: signal != 0 ? signal : (status >> 8) & 0xFF,
            signalled: signal != 0,
            standardError: ""
        ))
    }
}
