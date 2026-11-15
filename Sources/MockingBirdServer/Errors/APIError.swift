/// An error the server reports to a client (contract §4.4): an HTTP status, a stable
/// machine-readable `code`, and a human-readable `message`.
struct APIError: Error, Equatable, Codable, Sendable {
    let statusCode: Int
    let code: String
    let message: String

    static func invalidParameter(_ message: String) -> APIError {
        APIError(statusCode: 400, code: "invalid_parameter", message: message)
    }

    static func emptyBody() -> APIError {
        APIError(statusCode: 400, code: "empty_body", message: "request body is empty")
    }

    static func payloadTooLarge(limit: Int) -> APIError {
        APIError(statusCode: 413, code: "payload_too_large", message: "request body exceeds \(limit) bytes")
    }

    static func unsupportedMediaType(_ mediaType: String) -> APIError {
        APIError(statusCode: 415, code: "unsupported_media_type", message: "unsupported Content-Type '\(mediaType)'")
    }

    static func insufficientAudio(_ detail: String) -> APIError {
        APIError(statusCode: 422, code: "insufficient_audio", message: detail)
    }

    static func undecodableAudio(_ detail: String) -> APIError {
        APIError(statusCode: 422, code: "undecodable_audio", message: detail)
    }

    static func analysisFailed(_ detail: String) -> APIError {
        APIError(statusCode: 500, code: "analysis_failed", message: detail)
    }

    static func spawnFailed(_ detail: String) -> APIError {
        APIError(statusCode: 500, code: "spawn_failed", message: detail)
    }
}
