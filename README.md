# MockingBird

Detects the musical key of audio. It ships as three programs built from one Swift package:
a DSP command-line tool, an HTTP/WebSocket gateway that runs that tool, and a macOS SwiftUI app.

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│          MockingBird.app (SwiftUI, SPM target)           │
│    links MockingBirdCore + AudioSourceAVFoundation       │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│               mockingbird-server                         │
│   HTTP/WebSocket gateway · no DSP · Hummingbird 2.x      │
│   ProcessPool: bounded subprocess pool (default max 4)   │
│   GET /health · POST /analyze · WS /stream               │
└────────────────────────┬────────────────────────────────┘
                  spawns │ one process per request/connection
┌────────────────────────▼────────────────────────────────┐
│                   mockingbird (CLI)                      │
│   Reads PCM or audio files → KeyResult JSON on stdout    │
│   Input: file · stdin pipe · capture device              │
└────────────────────────┬────────────────────────────────┘
                   links │
┌────────────────────────▼────────────────────────────────┐
│                  MockingBirdCore                         │
│   Pure Swift DSP library · compiles on Linux and macOS   │
└─────────────────────────────────────────────────────────┘
```

Each program has one job. The CLI does DSP and never speaks HTTP; the server speaks HTTP
and never does DSP (it does not link `MockingBirdCore`); the app links Core in-process.

There is no Xcode project. The app is the `MockingBirdApp` executable target in
`Package.swift`, and `scripts/bundle-app.sh` wraps it into `MockingBird.app`.

| Target | Kind | Platforms | Job |
|---|---|---|---|
| `MockingBirdCore` | library | macOS, Linux | DSP: FFT, chroma, key detection, pipeline |
| `AudioSourceAVFoundation` | library | macOS | Microphone capture and file decoding via AVFoundation |
| `CMiniAudio` | C library | macOS, Linux | Vendored miniaudio plus the `mb_` C bridge |
| `AudioSourceMiniAudio` | library | macOS, Linux | Device capture and file decoding via miniaudio |
| `MockingBirdCLI` | executable `mockingbird` | macOS, Linux | The DSP CLI |
| `MockingBirdServer` | executable `mockingbird-server` | macOS, Linux | HTTP/WebSocket gateway |
| `MockingBirdApp` | executable | macOS | SwiftUI app |
| `MockingBirdTestSupport` | library | macOS, Linux | Shared test signals and helpers |

Apple-only targets are added to the manifest only on macOS, so `swift build` and
`swift test` work unchanged on Linux.

### Process pool

`mockingbird-server` treats subprocesses like a SQL connection pool:

- `--max-connections` (default 4) subprocesses alive at once.
- Each request or WebSocket connection gets one fresh `mockingbird` process; no reuse.
- Requests beyond the limit **wait** in FIFO order; they are never rejected.
- A slot is released when its process has exited, on every path including errors.

---

## DSP pipeline

```
Microphone / file / stdin
  → AudioSource (platform-specific)
  → AsyncThrowingStream<[Float], Error>
  → AnalysisPipeline (actor, one per job, owns its DSP stack)
        ↓ FFTProcessor
            Blackman window (-58 dB sidelobes), optional zero-padding
            vDSP on Apple platforms, pure-Swift RadixTwoFFT elsewhere
            → [Float] magnitudes (fftSize / 2 bins)
        ↓ ChromaExtractor
            Spectral peaks only: local maxima above 2 % of the window maximum
            Parabolic interpolation on log magnitude for the peak frequency
            65–2000 Hz, folded to 12 pitch classes
        ↓ ChromaAccumulator
            Combines un-normalised chroma across windows (ChromaAggregation)
        ↓ KeyDetector
            Pearson correlation against every profile in ProfileLibrary
            confidence = r clamped to [0, 1]
            → KeyResult (key, scaleName, category, confidence, alternates, timestamp)
```

One `KeyResult` is emitted per hop (`hopSize` samples) in every aggregation mode.

### Aggregation modes

| `ChromaAggregation` | Each result reflects | Used by |
|---|---|---|
| `.perWindow` | its own window only | diagnostics |
| `.cumulative` | every window since the stream started | whole-file answers: CLI default, `POST /analyze`, app file analysis |
| `.rolling(windows: n)` | the most recent `n` windows | live input: CLI `--continuous`, `WS /stream`, app Listen |

Live input uses about 15 s: `n = max(1, Int(15 * sampleRate / hopSize))` (322 at the defaults).
With `.cumulative`, the last result of a finite stream is the answer for the whole input.
Loud windows weigh more than quiet ones because chroma is accumulated before normalising.

`KeyResult.timestamp` is the audio position in seconds at the end of the analysed window,
`(windowIndex * hopSize + windowSize) / sampleRate`. It is deterministic, not wall-clock time.
A stream shorter than one window produces no result.

### Why Blackman

Its sidelobes sit near -58 dB, against about -31 dB for Hann, so a strong partial does
not leak into neighbouring pitch classes. Its main lobe is wide, though (about ±2
semitones at C4 with a 4096-sample window), which is why chroma is built from spectral
peaks rather than by summing every bin: summing put E2 on F and C2 on D.

### Why Pearson

Pearson correlation subtracts each vector's mean before comparing, so a profile only
scores well if the input's *shape* (which pitch classes stand out) matches. Earlier versions
used cosine similarity; measured on synthetic material it gave white noise a score of 0.95
and, against 192 largely overlapping profiles, always preferred a pentatonic scale. With
Pearson, white noise scores about 0.44, tonal material 0.79–0.93, and silence 0, so the
confidence value means something.

### Confidence

Guide values: tonal material 0.79–0.93, white noise about 0.44, silence 0. The app shows a
live result muted ("Listening…") while confidence is below 0.6.

---

## KeyResult JSON

`JSONEncoder` with sorted keys, one object per line:

```json
{"alternates":[{"category":"pentatonic","confidence":0.881,"key":"C","scaleName":"major pentatonic"}],"category":"major","confidence":0.924,"key":"C","scaleName":"major","timestamp":3.99}
```

- `key` is a `PitchClass` name: one of `C C# D D# E F F# G G# A A# B` (sharps only).
  Decoding also accepts the legacy integers 0–11.
- `category` is a `ScaleCategory`: `major minor mode blues jazz pentatonic symmetric custom`.
- `alternates` holds up to `--alternates` runner-ups, sorted by confidence, highest first.

---

## Key types

| Type | Kind | Description |
|---|---|---|
| `PitchClass` | `enum` | 12 cases, sharps only; Codable as `"C"` … `"B"` |
| `ScaleCategory` | `enum` | `.major .minor .mode .blues .jazz .pentatonic .symmetric .custom` |
| `KeyResult` | `struct` | key, scaleName, category, confidence (0–1), alternates, timestamp (audio seconds) |
| `ChromaVector` | `struct` | bins (`[Float]`, count 12), sampleRate, windowSize |
| `ChromaAggregation` | `enum` | `.perWindow`, `.cumulative`, `.rolling(windows:)` |
| `AudioConfig` | `struct` | sampleRate 44100, windowSize 4096, hopSize 2048, numAlternates 3, zeroPad false |
| `ScaleProfile` | `struct` | name, root, category, scaleName, weights (`[Float]`, count 12) |
| `ProfileLibrary` | `struct` | profiles, `static .default`; Codable, validated on decode |
| `AudioSource` | `protocol` | `start(sampleRate:) throws -> AsyncThrowingStream<[Float], Error>`, `stop()` |
| `AudioSourceError` | `enum` | `.permissionDenied .deviceUnavailable .formatUnsupported .deviceDisconnected .unknown` |
| `AnalysisPipeline` | `actor` | owns FFTProcessor, ChromaExtractor, ChromaAccumulator, KeyDetector |
| `PipelineError` | `enum` | typed errors with `ErrorContext` (component, operation, timestamp) |

---

## Scale profiles

`ProfileLibrary.default` ships all 12 transpositions of 16 scale types: **192 profiles**.

| Scale | Category | Notes |
|---|---|---|
| Major | `.major` | Temperley (1999) |
| Minor | `.minor` | Weights `[5, 2, 3.5, 4.5, 2, 4, 2, 4.5, 3.5, 2, 3, 3]`, covering natural and harmonic minor |
| Dorian | `.mode` | Church mode ii |
| Phrygian | `.mode` | Church mode iii |
| Lydian | `.mode` | Church mode iv |
| Mixolydian | `.mode` | Church mode v |
| Locrian | `.mode` | Church mode vii |
| Blues | `.blues` | 1 b3 4 b5 5 b7 |
| Jazz minor | `.jazz` | Melodic minor ascending |
| Bebop dominant | `.jazz` | 1 2 3 4 5 6 b7 7 |
| Bebop major | `.jazz` | 1 2 3 4 5 #5 6 7 |
| Major pentatonic | `.pentatonic` | 1 2 3 5 6 |
| Minor pentatonic | `.pentatonic` | 1 b3 4 5 b7 |
| Whole tone | `.symmetric` | Six equal steps |
| Diminished (HW) | `.symmetric` | Half-whole |
| Diminished (WH) | `.symmetric` | Whole-half |

Modes that share pitch classes (C major, D dorian, A minor) are told apart only by tonic
emphasis. To restrict detection to major and minor, pass a smaller library with `--profiles`.

A library file is JSON:

```json
{"profiles":[{"name":"C major","root":"C","category":"major","scaleName":"major","weights":[5,2,3.5,2,4.5,4,2,4.5,2,3.5,1.5,4]}]}
```

Decoding rejects an empty library or a profile without exactly 12 weights.

To add a scale to the default library: define a 12-element weight vector at C (index 0 = C
… 11 = B), add it to `templateProfiles` in `ProfileLibrary.swift`, and cover its 12
transpositions in `ProfileLibraryTests.swift`.

---

## Audio sources

All sources conform to `AudioSource` and deliver mono Float32 through
`AsyncThrowingStream<[Float], Error>`. Naming: `[Platform]Source`.

| Implementation | Platform | Input | Status |
|---|---|---|---|
| `FileSource` | any | raw mono Float32 LE file | done |
| `RawPCMSource` | any | raw mono Float32 LE on a `FileHandle` (stdin) | done |
| `AVFoundationSource` | macOS | microphone or named input device | done; live capture needs microphone permission |
| `AVFoundationFileSource` | macOS | WAV, AIFF, M4A, MP3, anything `AVAudioFile` reads | done |
| `MiniAudioSource` | Linux (also builds on macOS) | capture device by name or default | done; tested on the null backend only |
| `MiniAudioFileSource` | Linux (also builds on macOS) | WAV, FLAC, MP3 | done |

File sources downmix to mono, resample to the requested rate, and finish the stream at end
of file. A missing or undecodable file fails with `AudioSourceError`.

**Real-time rule:** the audio callback never allocates, locks, or calls into the Swift
runtime. Buffers are allocated at init; the miniaudio callback only writes into a lock-free
ring buffer that a Swift task drains.

---

## `mockingbird` (CLI)

```
mockingbird [options] [<file>]
```

| Flag | Default | Meaning |
|---|---|---|
| `<file>`, `--file <path>` | | Audio file to analyse |
| `--sample-rate <int>` | 44100 | Rate of raw PCM input; analysis rate for decoded and device input |
| `--window-size <int>` | 4096 | Analysis window, power of two |
| `--hop-size <int>` | 2048 | Samples between windows, 1…window size |
| `--alternates <int>` | 3 | Runner-up keys per result, ≥ 0 |
| `--zero-pad` | off | Zero-pad each window to twice its length before the FFT |
| `--profiles <path>` | built-in 192 | ProfileLibrary JSON file |
| `--device <name>` | | Capture device by name; `default` is the system default input |
| `--continuous` | off | Emit a rolling (~15 s) result every hop until input ends or the process is killed |
| `--format json\|line` | `json` | Output format |
| `--duration <seconds>` | none; 10 for device input without `--continuous` | Stop after this much audio |
| `--list-devices` | | Print capture device names, one per line |
| `--help`, `--version` | | Print to stdout and exit 0 |

**Input precedence:** `<file>`, then `--device`, then stdin if it is not a terminal, then the
default capture device.

**File types by extension:** `.raw`, `.pcm` and `.f32` are raw mono Float32 little-endian at
`--sample-rate`. Anything else is decoded (AVFoundation on macOS, miniaudio on Linux),
downmixed to mono, and resampled to `--sample-rate`. Stdin is always raw mono Float32 LE.

**Output** goes to stdout and nothing else does. Without `--continuous` there is exactly one
line, the whole-input (cumulative) result, when input ends. With `--continuous` there is one
line per hop, flushed as it is written.

`--format line` is tab-separated: timestamp, key and scale, confidence, alternates joined by
`; `:

```
3.99	C major	0.924	C major pentatonic 0.881; G mixolydian 0.842
```

**Errors** go to stderr as `mockingbird: error: <message>`.

| Exit code | Meaning |
|---|---|
| 0 | Success |
| 1 | Runtime failure (audio source or pipeline error) |
| 2 | Usage error (unknown flag, bad value) |
| 3 | Input ended before one full window; no result |
| 4 | Input unreadable (file missing or undecodable, invalid profiles file) |

Examples:

```bash
mockingbird song.m4a                                   # one line for the whole file
mockingbird --format line --alternates 1 song.wav
ffmpeg -i song.mp3 -f f32le -ar 44100 -ac 1 - | mockingbird
mockingbird --continuous --device default              # live, until Ctrl-C
mockingbird --device default --duration 5
mockingbird --list-devices
```

---

## `mockingbird-server`

```bash
mockingbird-server --host 127.0.0.1 --port 7742 --max-connections 4
```

| Flag | Default | Meaning |
|---|---|---|
| `--port <int>` | 7742 | Listen port |
| `--host <string>` | 127.0.0.1 | Listen address |
| `--max-connections <int>` | 4 | Subprocesses alive at once; extra work waits |
| `--mockingbird <path>` | `mockingbird` next to the server executable | CLI binary to spawn |
| `--max-body-bytes <int>` | 104857600 | Largest accepted `POST /analyze` body |

### Routes

| Route | Behaviour |
|---|---|
| `GET /health` | `200`, body `ok` |
| `POST /analyze` | Body is audio. `200 application/json` with one KeyResult (whole input) |
| `WS /stream` | Live analysis over a WebSocket (below) |

Both analysis routes take optional query parameters, validated and passed to the CLI as
arguments (never through a shell): `sampleRate`, `windowSize`, `hopSize`, `alternates`,
`zeroPad`. Profiles and devices are not exposed.

```bash
curl -s localhost:7742/health
curl -s -X POST --data-binary @song.raw -H 'Content-Type: application/octet-stream' localhost:7742/analyze
curl -s -X POST --data-binary @song.wav -H 'Content-Type: audio/wav' 'localhost:7742/analyze?alternates=1'
```

### `POST /analyze` content types

| Content-Type | Treated as |
|---|---|
| none, `application/octet-stream`, `audio/pcm` | raw mono Float32 LE, piped to the CLI's stdin |
| `audio/wav`, `audio/x-wav`, `audio/wave` | WAV file |
| `audio/aiff`, `audio/x-aiff` | AIFF file |
| `audio/mp4`, `audio/m4a`, `audio/x-m4a` | M4A file |
| `audio/mpeg` | MP3 file |
| `audio/flac` | FLAC file |
| anything else | `415` |

Encoded bodies are written to a temporary file, analysed, and removed.

### Errors

Body: `{"error":{"code":"<code>","message":"<text>"}}`.

| Status | `code` | When |
|---|---|---|
| 400 | `invalid_parameter` | A query parameter is not a valid number/boolean or is out of range |
| 400 | `empty_body` | No audio |
| 413 | `payload_too_large` | Body over `--max-body-bytes` |
| 415 | `unsupported_media_type` | Content type not in the table above |
| 422 | `insufficient_audio` | Less than one analysis window (CLI exit 3) |
| 422 | `undecodable_audio` | File could not be decoded (CLI exit 4) |
| 500 | `analysis_failed` | Any other CLI failure; message carries its stderr |
| 500 | `spawn_failed` | The CLI could not be started |

### WebSocket protocol (`/stream`)

1. Connect to `ws://host:7742/stream` (same query parameters as `/analyze`). The socket is
   upgraded at once; if the pool is full, frames are simply not read until a slot frees up.
2. Send **binary** frames of mono Float32 LE PCM, any size up to 1 MiB; frames need not be
   4-byte aligned.
3. Receive one **text** frame per result: a KeyResult JSON object (rolling ~15 s window,
   one per hop).
4. Send the text frame `end` to finish. The server closes the CLI's stdin, forwards the
   remaining results, and closes normally.

If the client disconnects without `end`, the subprocess is terminated. On failure the server
sends one text frame with the error object above, then closes with code 1011.

The server has no request timeout: a stalled client holds its slot until it disconnects.
It is meant as a local gateway.

---

## macOS app

`MockingBird.app` shows the detected key large, its scale and confidence, and the runner-up
keys.

- **Listen** asks for microphone permission (first time only) and shows a rolling ~15 s
  result that updates every hop. The microphone is never opened until you press Listen.
- **Drop an audio file** on the window, or use **Open…** (⌘O), to analyse a whole file.
- Starting one stops the other. **Stop** returns to idle.
- `open build/MockingBird.app --args song.wav` analyses `song.wav` at launch.

If microphone access was denied, the app says so; allow it in System Settings › Privacy &
Security › Microphone. The bundle is ad-hoc signed, so macOS may ask again after a rebuild.

---

## Error handling

Two failure categories, no others:

| Category | Mechanism | When |
|---|---|---|
| Invariant violation | `precondition()`: crash | The caller broke a contract (wrong buffer size, empty library) |
| System constraint failure | throw `PipelineError` with `ErrorContext` | A valid request the runtime cannot fulfil (device unavailable) |

The CLI turns failures into a stderr message and an exit code; the server turns them into a
JSON error body and status code. No silent recovery, retry, or fallback.

---

## Building and testing

**Requirements:** Swift 6.2 or newer (the pinned swift-nio and swift-log need it), macOS 14+
for the app. Xcode is optional. Docker for the Linux targets.

```bash
make help            # list targets
make build           # swift build
make test            # every test suite, via ./scripts/test.sh
make test-core       # one suite: test-core, test-cli, test-server, test-miniaudio, test-app
make app             # build/MockingBird.app, ad-hoc signed
make run-app         # open it
make linux-build     # swift build in the swift:6.2 container (scripts/linux.sh)
make linux-test      # swift test in the swift:6.2 container
make clean           # removes .build/ and build/
```

Tests use Swift Testing (`import Testing`) only. With **Command Line Tools** (no Xcode),
plain `swift test` cannot find the Testing framework, so always run tests through the script,
which adds the framework and rpath flags and forwards its arguments to `swift test`:

```bash
./scripts/test.sh
./scripts/test.sh --filter MockingBirdCoreTests
```

With **Xcode** installed, `./scripts/test.sh` is the same as `swift test`, and both work.

On **Linux**, `swift build` and `swift test` work directly; the Apple-only targets are left
out of the manifest. From a Mac, use `make linux-build` / `make linux-test`.

The app needs no Xcode project: `./scripts/bundle-app.sh` (what `make app` runs) builds the
`MockingBirdApp` product in release mode and assembles `build/MockingBird.app` around it with
`Support/MockingBirdApp/Info.plist`.

CI (`.github/workflows/ci.yml`) runs `swift build`, `swift test` and the app bundle on
macOS with Xcode 26, and `swift build` / `swift test` in the `swift:6.2` container on Linux.

---

## Known limits

- **Accuracy is verified on synthetic signals only:** sines with harmonics, cadences in all
  12 major and minor keys, scale melodies. Real recordings with percussion, inharmonic
  timbres, detuning or modulation are untested.
- Related modes (C major / D dorian / A minor) are distinguished only by tonic emphasis; the
  full library will sometimes name a relative mode on real music.
- The 15 s live window and the 0.6 "unsure" threshold are reasoned defaults, not tuned.
- Live capture needs microphone permission, which only a person can grant.
- Linux device capture is untested: CI and Docker have no audio device, so only miniaudio's
  null backend and file decoding are exercised.
- The app is ad-hoc signed only: not notarized, not distributable.

---

## Project links

| Resource | URL |
|---|---|
| Wiki | https://www.notion.so/344fe55904c881d69fa8eaa22ae46ebe |
| Coding contract | https://www.notion.so/346fe55904c881578e75e69e3c82bea1 |
| Tickets | https://www.notion.so/fef43cffe2a941c1b0de81e835840e08 |
| Sprints | https://www.notion.so/bbbdf2443ad646d1a28bc6378f5c499f |
