import Foundation
import MockingBirdCore

/// Renders a `KeyResult` as one output line (without the trailing newline).
struct ResultFormatter: Sendable {
    let format: OutputFormat

    /// - Throws: `EncodingError` if JSON encoding fails.
    func format(_ result: KeyResult) throws -> String {
        switch format {
        case .json:
            return try json(result)
        case .line:
            return line(result)
        }
    }

    // MARK: - Private

    private func json(_ result: KeyResult) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(result), as: UTF8.self)
    }

    /// `timestamp<TAB>key scale<TAB>confidence<TAB>alternates`, alternates joined by `"; "`.
    private func line(_ result: KeyResult) -> String {
        let alternates = result.alternates
            .map { "\($0.key) \($0.scaleName) \(String(format: "%.3f", $0.confidence))" }
            .joined(separator: "; ")
        return [
            String(format: "%.2f", result.timestamp),
            "\(result.key) \(result.scaleName)",
            String(format: "%.3f", result.confidence),
            alternates,
        ].joined(separator: "\t")
    }
}
