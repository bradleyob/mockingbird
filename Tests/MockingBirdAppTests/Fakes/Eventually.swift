/// Polls `condition` on the main actor until it holds or `timeout` seconds pass.
/// Returns whether it held.
@MainActor
func eventually(timeout: Double = 5, _ condition: @MainActor () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .milliseconds(Int(timeout * 1000)))
    while clock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}
