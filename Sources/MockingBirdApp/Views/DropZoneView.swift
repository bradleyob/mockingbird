import SwiftUI
import UniformTypeIdentifiers

/// Accepts an audio file by drag and drop, or through an Open… panel.
struct DropZoneView: View {
    let onFile: (URL) -> Void
    @State private var isTargeted = false
    @State private var isImporting = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("Drop an audio file here")
                .foregroundStyle(.secondary)
            Button("Open…") { isImporting = true }
                .keyboardShortcut("o", modifiers: .command)
        }
        .frame(maxWidth: .infinity, minHeight: 110)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.5))
        )
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: \.isFileURL) else { return false }
            onFile(url)
            return true
        } isTargeted: { isTargeted = $0 }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.audio]) { outcome in
            if case .success(let url) = outcome {
                onFile(url)
            }
        }
    }
}
