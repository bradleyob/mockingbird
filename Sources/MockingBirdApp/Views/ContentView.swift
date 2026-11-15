import SwiftUI

/// The single window: detected key, alternates, a drop zone, and the Listen button.
struct ContentView: View {
    let viewModel: KeyDetectionViewModel

    var body: some View {
        let presentation = KeyPresentation(state: viewModel.state, result: viewModel.result)
        VStack(spacing: 20) {
            KeyDisplayView(presentation: presentation)
            AlternatesView(alternates: presentation.alternates, isTentative: presentation.isTentative)
            Spacer(minLength: 0)
            DropZoneView(onFile: { viewModel.analyzeFile(at: $0) })
            ListenButton(
                isRunning: viewModel.isBusy,
                start: { viewModel.startListening() },
                stop: { viewModel.stop() }
            )
        }
        .padding(24)
        .frame(minWidth: 420, minHeight: 520)
    }
}
