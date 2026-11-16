import Testing
@testable import MockingBirdCore

@Suite("AudioConfig")
struct AudioConfigTests {
    @Test("defaults are 44100 / 4096 / 2048 / 3 / false")
    func defaults() {
        let config = AudioConfig()
        #expect(config.sampleRate == 44100)
        #expect(config.windowSize == 4096)
        #expect(config.hopSize == 2048)
        #expect(config.numAlternates == 3)
        #expect(config.zeroPad == false)
        #expect(config.fftSize == 4096)
    }

    @Test("zero padding doubles fftSize")
    func zeroPadFFTSize() {
        #expect(AudioConfig(zeroPad: true).fftSize == 8192)
    }
}
