import Foundation
import Testing
@testable import MockingBirdCore

@Suite("Codable round trips")
struct CodableRoundTripTests {
    private func roundTrip<T: Codable>(_ value: T) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
    }

    @Test("ChromaVector")
    func chromaVector() throws {
        let value = ChromaVector(bins: (0..<12).map { Float($0) / 12 }, sampleRate: 48000, windowSize: 8192)
        #expect(try roundTrip(value) == value)
    }

    @Test("AudioConfig")
    func audioConfig() throws {
        let value = AudioConfig(sampleRate: 48000, windowSize: 8192, hopSize: 1024, numAlternates: 1, zeroPad: true)
        #expect(try roundTrip(value) == value)
    }

    @Test("ScaleProfile")
    func scaleProfile() throws {
        let value = try #require(ProfileLibrary.default.profiles.last)
        #expect(try roundTrip(value) == value)
    }

    @Test("ScaleProfile encodes root as a pitch-class string")
    func scaleProfileRootIsString() throws {
        let value = try #require(ProfileLibrary.default.profiles.first { $0.root == .fSharp })
        let json = String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
        #expect(json.contains(#""root":"F#""#))
    }

    @Test("ProfileLibrary")
    func profileLibrary() throws {
        let value = ProfileLibrary.default
        #expect(try roundTrip(value).profiles == value.profiles)
    }

    @Test("ChromaAggregation", arguments: [ChromaAggregation.perWindow, .cumulative, .rolling(windows: 20)])
    func chromaAggregation(value: ChromaAggregation) throws {
        #expect(try roundTrip(value) == value)
    }

    @Test("PipelineError")
    func pipelineError() throws {
        let context = ErrorContext(operation: "read", component: "FileSource",
                                   underlyingDescription: "gone", timestamp: Date(timeIntervalSince1970: 1000))
        let values: [PipelineError] = [
            .fftSetupFailed(context),
            .audioSourceFailed(.unknown("boom"), context),
            .pipelineStopped(context),
        ]
        for value in values {
            #expect(try roundTrip(value).description == value.description)
        }
    }
}
