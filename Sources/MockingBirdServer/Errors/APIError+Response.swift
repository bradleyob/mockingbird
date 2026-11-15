import Foundation
import Hummingbird

extension APIError {
    /// The `{"error":{...}}` JSON text sent as an HTTP body or a WebSocket text frame.
    var json: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        do {
            return String(decoding: try encoder.encode(APIErrorBody(self)), as: UTF8.self)
        } catch {
            // Encoding two strings cannot fail; keep a well-formed body regardless.
            return #"{"error":{"code":"\#(code)","message":"internal error"}}"#
        }
    }

    /// The HTTP response for this error.
    var response: Response {
        Response(
            status: HTTPResponse.Status(code: statusCode),
            headers: [.contentType: "application/json"],
            body: ResponseBody(byteBuffer: ByteBuffer(string: json))
        )
    }
}
