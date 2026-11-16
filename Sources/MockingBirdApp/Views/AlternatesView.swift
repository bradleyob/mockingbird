import MockingBirdCore
import SwiftUI

/// Runner-up keys, one row each, with their confidence.
struct AlternatesView: View {
    let alternates: [KeyResult.Alternate]
    let isTentative: Bool

    var body: some View {
        if !alternates.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Also possible")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                ForEach(Array(alternates.enumerated()), id: \.offset) { _, alternate in
                    HStack {
                        Text("\(String(describing: alternate.key)) \(alternate.scaleName)")
                        Spacer()
                        ProgressView(value: Double(alternate.confidence))
                            .frame(width: 80)
                        Text(String(format: "%.2f", alternate.confidence))
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .foregroundStyle(isTentative ? .secondary : .primary)
            .padding(12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
