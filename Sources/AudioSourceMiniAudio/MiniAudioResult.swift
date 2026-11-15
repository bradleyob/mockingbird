import CMiniAudio

/// Text for an `mb_result` from the C bridge.
enum MiniAudioResult {
    static func describe(_ result: mb_result) -> String {
        "\(String(cString: mb_result_description(result))) (\(result))"
    }
}
