/// JSON shape of every error response and error frame:
/// `{"error":{"code":"<code>","message":"<text>"}}`.
struct APIErrorBody: Codable, Equatable, Sendable {
    struct Detail: Codable, Equatable, Sendable {
        let code: String
        let message: String
    }

    let error: Detail

    init(_ apiError: APIError) {
        self.error = Detail(code: apiError.code, message: apiError.message)
    }
}
