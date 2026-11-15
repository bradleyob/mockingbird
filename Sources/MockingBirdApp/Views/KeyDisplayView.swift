import SwiftUI

/// The detected key, large, with its scale, a confidence bar, and a status line.
/// Muted while the result is tentative (still listening, or confidence below 0.6).
struct KeyDisplayView: View {
    let presentation: KeyPresentation

    var body: some View {
        VStack(spacing: 8) {
            Text(presentation.keyName ?? "–")
                .font(.system(size: 96, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(presentation.isTentative || presentation.keyName == nil ? .secondary : .primary)
                .contentTransition(.numericText())
                .accessibilityLabel(presentation.keyName.map { "Key \($0)" } ?? "No key yet")

            Text(presentation.scaleName ?? " ")
                .font(.title2)
                .foregroundStyle(.secondary)

            ProgressView(value: Double(presentation.confidence ?? 0))
                .progressViewStyle(.linear)
                .tint(presentation.isTentative ? .gray : .accentColor)
                .frame(maxWidth: 240)
                .accessibilityLabel("Confidence")
                .accessibilityValue(Text(confidenceText))

            Text(confidenceText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Text(presentation.status)
                .font(.callout)
                .foregroundStyle(presentation.isError ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .animation(.default, value: presentation.keyName)
    }

    private var confidenceText: String {
        guard let confidence = presentation.confidence else { return "confidence –" }
        return String(format: "confidence %.2f", confidence)
    }
}
