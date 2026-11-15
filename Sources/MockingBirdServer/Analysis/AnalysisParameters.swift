/// Optional analysis settings a client passes as query parameters (contract §4.4).
/// `nil` means "use the CLI's default".
struct AnalysisParameters: Equatable, Sendable {
    var sampleRate: Int?
    var windowSize: Int?
    var hopSize: Int?
    var alternates: Int?
    var zeroPad: Bool = false
}
