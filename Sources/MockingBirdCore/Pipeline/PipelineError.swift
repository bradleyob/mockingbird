import Foundation

/// All system-constraint failures that propagate out of `AnalysisPipeline`.
///
/// These represent valid requests the runtime could not fulfill — not caller
/// contract violations (those are `precondition()`s that crash immediately).
public enum PipelineError: Error, Codable, Sendable {
    case fftSetupFailed(ErrorContext)
    case chromaExtractionFailed(ErrorContext)
    case keyDetectionFailed(ErrorContext)
    case audioSourceFailed(AudioSourceError, ErrorContext)
    case pipelineStopped(ErrorContext)
}

/// Contextual metadata attached to every thrown `PipelineError`.
public struct ErrorContext: Codable, Sendable {
    /// Short description of what was attempted.
    public let operation: String
    /// Component that threw (e.g. "FFTProcessor", "ChromaExtractor").
    public let component: String
    /// Optional underlying OS/framework error description.
    public let underlyingDescription: String?
    /// Timestamp of the failure.
    public let timestamp: Date

    public init(
        operation: String,
        component: String,
        underlyingDescription: String? = nil,
        timestamp: Date = Date()
    ) {
        self.operation = operation
        self.component = component
        self.underlyingDescription = underlyingDescription
        self.timestamp = timestamp
    }
}

extension PipelineError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .fftSetupFailed(let ctx):
            return "[\(ctx.component)] FFT setup failed during '\(ctx.operation)'"
                + (ctx.underlyingDescription.map { ": \($0)" } ?? "")
        case .chromaExtractionFailed(let ctx):
            return "[\(ctx.component)] Chroma extraction failed during '\(ctx.operation)'"
                + (ctx.underlyingDescription.map { ": \($0)" } ?? "")
        case .keyDetectionFailed(let ctx):
            return "[\(ctx.component)] Key detection failed during '\(ctx.operation)'"
                + (ctx.underlyingDescription.map { ": \($0)" } ?? "")
        case .audioSourceFailed(let sourceError, let ctx):
            return "[\(ctx.component)] Audio source error (\(sourceError)) during '\(ctx.operation)'"
                + (ctx.underlyingDescription.map { ": \($0)" } ?? "")
        case .pipelineStopped(let ctx):
            return "[\(ctx.component)] Pipeline stopped during '\(ctx.operation)'"
                + (ctx.underlyingDescription.map { ": \($0)" } ?? "")
        }
    }
}
