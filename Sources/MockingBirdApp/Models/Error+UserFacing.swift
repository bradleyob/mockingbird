import Foundation
import MockingBirdCore

extension Error {
    /// A short description suitable for showing in the window. Audio-source failures are
    /// unwrapped from `PipelineError` so the user sees the cause ("audio device
    /// disconnected"), not the pipeline plumbing around it.
    var userFacingDescription: String {
        switch self {
        case let error as AudioSourceError:
            return error.description
        case let error as PipelineError:
            if case .audioSourceFailed(let sourceError, _) = error {
                return sourceError.description
            }
            return error.description
        default:
            return localizedDescription
        }
    }
}
