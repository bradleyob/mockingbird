import SwiftUI

/// Starts live listening, or stops whatever is running (listening or file analysis).
struct ListenButton: View {
    let isRunning: Bool
    let start: () -> Void
    let stop: () -> Void

    var body: some View {
        Button(action: isRunning ? stop : start) {
            Label(isRunning ? "Stop" : "Listen", systemImage: isRunning ? "stop.fill" : "mic.fill")
                .frame(minWidth: 120)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut("l", modifiers: .command)
    }
}
