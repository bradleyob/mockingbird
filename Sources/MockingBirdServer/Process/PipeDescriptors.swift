import Foundation
#if canImport(Glibc)
import Glibc
#endif

/// A freshly created pipe. Both ends are marked close-on-exec, so other children never
/// inherit them (the child's own ends are `dup2`ed onto 0/1/2, which clears the flag on the
/// copies it keeps). `pipe2(O_CLOEXEC)` would close the tiny window between `pipe` and
/// `fcntl`, but it is not available on Darwin.
struct PipeDescriptors: Sendable {
    struct CreationFailed: Error, CustomStringConvertible {
        let errno: Int32
        var description: String { String(cString: strerror(errno)) }
    }

    let read: CInt
    let write: CInt

    init() throws(CreationFailed) {
        var descriptors: [CInt] = [-1, -1]
        guard pipe(&descriptors) == 0 else {
            throw CreationFailed(errno: errno)
        }
        for descriptor in descriptors where fcntl(descriptor, F_SETFD, FD_CLOEXEC) != 0 {
            let failure = errno
            descriptors.forEach { Self.close($0) }
            throw CreationFailed(errno: failure)
        }
        read = descriptors[0]
        write = descriptors[1]
    }

    /// Closes a descriptor this process still owns.
    static func close(_ descriptor: CInt) {
        #if canImport(Glibc)
        _ = Glibc.close(descriptor)
        #else
        _ = Darwin.close(descriptor)
        #endif
    }
}
