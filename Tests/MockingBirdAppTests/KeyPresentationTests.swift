import MockingBirdCore
import Testing
@testable import MockingBirdApp

@Suite struct KeyPresentationTests {
    private func result(confidence: Float) -> KeyResult {
        KeyResult(
            key: .fSharp,
            scaleName: "minor",
            category: .minor,
            confidence: confidence,
            alternates: [KeyResult.Alternate(key: .a, scaleName: "major", category: .major, confidence: 0.7)]
        )
    }

    @Test func idleWithoutResultPromptsTheUser() {
        let presentation = KeyPresentation(state: .idle, result: nil)
        #expect(presentation.keyName == nil)
        #expect(presentation.isTentative == false)
        #expect(presentation.status.contains("Listen"))
    }

    @Test func confidentListeningShowsKeyAndScale() {
        let presentation = KeyPresentation(state: .listening, result: result(confidence: 0.85))
        #expect(presentation.keyName == "F#")
        #expect(presentation.scaleName == "minor")
        #expect(presentation.confidence == 0.85)
        #expect(presentation.isTentative == false)
    }

    @Test func lowConfidenceWhileListeningIsTentative() {
        let presentation = KeyPresentation(state: .listening, result: result(confidence: 0.59))
        #expect(presentation.isTentative)
        #expect(presentation.status == "Listening…")
    }

    @Test func listeningBeforeFirstResultIsTentative() {
        let presentation = KeyPresentation(state: .listening, result: nil)
        #expect(presentation.isTentative)
        #expect(presentation.keyName == nil)
        #expect(presentation.status == "Listening…")
    }

    @Test func thresholdIsSixTenths() {
        #expect(KeyPresentation.tentativeThreshold == 0.6)
        #expect(KeyPresentation(state: .listening, result: result(confidence: 0.6)).isTentative == false)
    }

    @Test func finishedFileNamesTheFile() {
        let presentation = KeyPresentation(state: .finished("song.wav"), result: result(confidence: 0.4))
        #expect(presentation.keyName == "F#")
        #expect(presentation.status == "song.wav")
        #expect(presentation.isTentative == false)
    }

    @Test func analyzingFileSaysSo() {
        let presentation = KeyPresentation(state: .analyzingFile("song.wav"), result: nil)
        #expect(presentation.status == "Analysing song.wav…")
    }

    @Test func failureShowsTheMessage() {
        let presentation = KeyPresentation(state: .failed("boom"), result: nil)
        #expect(presentation.status == "boom")
        #expect(presentation.isError)
    }

    @Test func alternatesArePassedThrough() {
        let presentation = KeyPresentation(state: .listening, result: result(confidence: 0.9))
        #expect(presentation.alternates.map(\.key) == [.a])
    }
}
