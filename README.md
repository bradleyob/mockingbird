# MockingBird

Detects the musical key of an audio snippet. Ships as a pure DSP CLI binary, an HTTP/WebSocket gateway, and a macOS SwiftUI app.

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    MockingBird.app (SwiftUI)             │
│           links MockingBirdCore in-process               │
└────────────────────────┬────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────┐
│               mockingbird-server                         │
│   HTTP/WebSocket gateway · no DSP · Hummingbird 2.x      │
│   ProcessPool: bounded subprocess pool (default max 4)   │
│   POST /analyze · WebSocket /stream                      │
└────────────────────────┬────────────────────────────────┘
                    spawns │ one process per connection
┌────────────────────────▼────────────────────────────────┐
│                   mockingbird (CLI)                      │
│   Reads PCM → writes KeyResult JSON to stdout            │
│   Input: stdin pipe · --file path · live mic             │
│   No HTTP · no platform UI                              │
└────────────────────────┬────────────────────────────────┘
                         │ links
┌────────────────────────▼────────────────────────────────┐
│                  MockingBirdCore                         │
│   Pure Swift DSP library · zero platform imports         │
│   Compiles on Linux and macOS                           │
└─────────────────────────────────────────────────────────┘
```

### Process Pool

`mockingbird-server` treats connections like a SQL connection pool:

- `maxConnections` (default 4, `--max-connections` flag)
- Each active connection gets one dedicated `mockingbird` subprocess
- Connections beyond the limit **queue** — never rejected
- No process reuse across connections; each gets a fresh process

---

## DSP Pipeline

```
Microphone / file / stdin
  → AudioSource (platform-specific)
  → AsyncThrowingStream<[Float], Error>
  → AnalysisPipeline (actor, one per job)
        ↓ FFTProcessor
            Blackman window (-58 dB sidelobe)
            vDSP_fft_zrip (real in-place FFT)
            → [Float] magnitudes (fftSize/2 bins)
        ↓ ChromaExtractor
            Bin → pitch class via MIDI frequency mapping
            65–2000 Hz range · octave folding
            L2-normalized 12-bin ChromaVector
        ↓ KeyDetector
            Cosine similarity against ProfileLibrary
            Rescale scores to [0, 1] confidence
            → KeyResult (key, scaleName, category, confidence, alternates)
```

### Why Blackman Window

The Blackman window achieves ~-58 dB sidelobe suppression vs ~-31 dB for Hann. The extra rejection prevents energy from strong partials leaking into adjacent pitch-class bins — critical for accurate chroma extraction from harmonic instruments.

### Why Cosine Similarity

Cosine similarity of two L2-normalized vectors reduces to a dot product. Pearson correlation subtracts the vector means before scoring, which unfairly penalizes diatonic profiles (7 notes) relative to pentatonic profiles (5 notes) when the input is a sparse chord. Cosine similarity matches the original Krumhansl-Schmuckler formulation and handles real-world sparse inputs correctly.

---

## Key Types

| Type | Kind | Description |
|---|---|---|
| `PitchClass` | `enum` | 12 cases, sharps only (C, C#, D … B) |
| `ScaleCategory` | `enum` | `.major .minor .mode .blues .jazz .pentatonic .symmetric .custom` |
| `KeyResult` | `struct` | key, scaleName, category, confidence (0–1), alternates (max 3), timestamp |
| `ChromaVector` | `struct` | bins ([Float] count==12), sampleRate, windowSize |
| `AudioConfig` | `struct` | sampleRate=44100, windowSize=4096, hopSize=2048, numAlternates=3, zeroPad=false |
| `ScaleProfile` | `struct` | name, root, category, weights ([Float] count==12), Codable |
| `ProfileLibrary` | `struct` | profiles, static `.default` |
| `AudioSource` | `protocol` | `start(sampleRate:) throws -> AsyncThrowingStream<[Float], Error>`, `stop()` |
| `AudioSourceError` | `enum` | `.permissionDenied .deviceUnavailable .formatUnsupported .deviceDisconnected .unknown` |
| `AnalysisPipeline` | `actor` | owns FFTProcessor + ChromaExtractor + KeyDetector exclusively |
| `PipelineError` | `enum` | typed errors with `ErrorContext` (component, operation, timestamp) |

---

## Scale Profiles

The default `ProfileLibrary` ships **all 12 transpositions** of each scale type — 156 profiles total:

| Scale | Category | Description |
|---|---|---|
| Major | `.major` | Temperley (1999) |
| Natural minor | `.minor` | Temperley (1999) |
| Dorian | `.mode` | Church mode ii |
| Phrygian | `.mode` | Church mode iii |
| Lydian | `.mode` | Church mode iv |
| Mixolydian | `.mode` | Church mode v |
| Locrian | `.mode` | Church mode vii |
| Blues | `.blues` | 1 b3 4 b5 5 b7 |
| Jazz minor | `.jazz` | Melodic minor ascending |
| Major pentatonic | `.pentatonic` | 1 2 3 5 6 |
| Minor pentatonic | `.pentatonic` | 1 b3 4 5 b7 |
| Whole tone | `.symmetric` | 6-note equal-interval |
| Diminished (HW) | `.symmetric` | Half-whole alternating |
| Diminished (WH) | `.symmetric` | Whole-half alternating |

To add a new scale: define a 12-element normalized weight vector (index 0=C … 11=B) at C root, add it to `templateProfiles` in `ProfileLibrary.swift`, and add 12-transposition test coverage in `ProfileLibraryTests.swift`.

---

## Audio Source Abstraction

All audio sources conform to the `AudioSource` protocol and deliver via `AsyncThrowingStream<[Float], Error>`. Naming convention: `[Platform]Source`.

| Implementation | Platform | Status |
|---|---|---|
| `AVFoundationSource` | macOS / iOS | ✅ Sprint 1 |
| `MiniAudioSource` | Linux / POSIX | 🔲 Sprint 2 (MB-11) |
| `FileSource` | Any | ✅ Sprint 1 |
| `RawPCMSource` | Any (stdin) | ✅ Sprint 1 |

**Audio callback rule:** The real-time callback path must never allocate, lock, or call the Swift runtime. Pre-allocate all buffers at `init`. This constraint applies to `AudioSource` implementations only — DSP layer components (`FFTProcessor`, `ChromaExtractor`, `KeyDetector`) run on the actor thread and may allocate freely.

---

## Error Handling

Two failure categories, no others:

| Category | Mechanism | When |
|---|---|---|
| Invariant violation | `precondition()` — crash immediately | Caller broke a contract (e.g. wrong buffer size) |
| System constraint failure | `throw PipelineError` with `ErrorContext` | Valid request, runtime can't fulfill it (e.g. device unavailable) |

`PipelineError` is `Codable`. CLI renders it to stderr with non-zero exit. HTTP API renders it as a JSON body with an appropriate status code. No silent recovery, no retry, no fallback.

---

## Binaries

### `mockingbird`

```bash
mockingbird                          # live mic → stdout KeyResult JSON
mockingbird --file audio.raw         # file input
ffmpeg -i song.mp3 -f f32le -ar 44100 -ac 1 - | mockingbird  # stdin pipe
```

Output (one JSON object per analysis window, newline-delimited):
```json
{"alternates":[...],"category":"major","confidence":0.91,"key":"C","scaleName":"major","timestamp":1.2}
```

### `mockingbird-server`

```bash
mockingbird-server \
  --host 0.0.0.0 \
  --port 8080 \
  --max-connections 4 \
  --binary /usr/local/bin/mockingbird
```

Routes (Sprint 2):
- `POST /analyze` — submit audio, receive KeyResult JSON
- `GET /stream` (WebSocket) — real-time key detection stream
- `GET /health` — liveness check

---

## Building

**Requirements:** Xcode 16+, Swift 6, macOS 14+

```bash
# Core library only
swift build --target MockingBirdCore

# All targets
swift build

# Run tests
swift test --filter MockingBirdCoreTests
```

---

## Project Links

| Resource | URL |
|---|---|
| Wiki | https://www.notion.so/344fe55904c881d69fa8eaa22ae46ebe |
| Coding Contract | https://www.notion.so/346fe55904c881578e75e69e3c82bea1 |
| Tickets | https://www.notion.so/fef43cffe2a941c1b0de81e835840e08 |
| Sprints | https://www.notion.so/bbbdf2443ad646d1a28bc6378f5c499f |
