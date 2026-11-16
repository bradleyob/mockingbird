# Finish MockingBird — execution plan (2026-11-15)

Four parallel tracks, one Opus agent each, on separate worktrees off `develop`, preceded by a
small **Phase 0** contract commit applied by the integrator. No pushing, no PRs, no Notion edits.

Companion file: `docs/plans/2026-11-15-phase0-contract.patch` (verified: applies cleanly to
`develop` @ `8759174`, `swift build` passes, `./scripts/test.sh` passes under Command Line Tools,
and on Linux `swift:6.2` everything except Core compiles).

---

## 1. What the investigation found

These were verified by experiment, not read off the docs. They shape the plan.

| # | Finding | Evidence | Owner |
|---|---|---|---|
| 1 | **Core does not compile on Linux.** `FFTProcessor`, `ChromaExtractor`, `KeyDetector` all `import Accelerate`. | `docker run swift:6.2 swift build --target MockingBirdCore` → `no such module 'Accelerate'` | A |
| 2 | **Detection is inaccurate.** Over 60 synthetic pieces (12 roots x major cadence, natural-minor cadence, harmonic-minor cadence, major scale melody, minor scale melody) the current code gets the exact key on 30/60 with the default library, and per-window results on a melody are noise (Twinkle in C: top votes G minor pentatonic, C minor pentatonic). | scratch probe | A |
| 3 | Cause 1: **spectral leakage.** Every FFT bin is summed into chroma; with a 4096 Blackman window the main lobe spans about ±32 Hz, i.e. ±2 semitones at C4. E2 maps to F, C2 maps to D. | single-tone probe | A |
| 4 | Cause 2: **no aggregation.** One `KeyResult` per 93 ms window, each from that window alone. | code + probe | A |
| 5 | Cause 3: **cosine similarity against 156 near-identical profiles** always prefers pentatonic (0/60 exact once leakage is fixed) and gives white noise a score of 0.95. Pearson gives noise 0.44 and tonal material 0.79–0.93. | probe | A |
| 6 | Cause 4: the "minor" profile is Temperley's harmonic-minor-leaning one (b7 = 1.5, natural 7 = 4.0), so natural-minor material goes to the relative major or dorian. | probe | A |
| 7 | **Confidence is meaningless**: min-max rescaling makes the winner always exactly 1.0. | output | A |
| 8 | **Zero-pad FFT carries state between calls.** The in-place FFT overwrites the upper halves of `realPart`/`imagPart`, which the code assumes stay zero. Same input twice gives different output. | probe | A |
| 9 | `PitchClass` encodes as an integer (`"key":0`); README and MB-2 specify `"key":"C"`. | CLI output | A |
| 10 | `KeyResult.timestamp` is wall-clock since start (0.057 s for a 4 s file), not position in the audio. | CLI output | A |
| 11 | `RawPCMSource` assumes every pipe read is a multiple of 4 bytes; a short read misaligns all later samples. | code | A |
| 12 | `Package.resolved` pins swift-log 1.12.0 / swift-nio 2.98.0, which need Swift tools 6.2. `swift:6.0` cannot resolve; CI's Xcode 16.3 (Swift 6.1) almost certainly cannot either. | docker | D (CI) |
| 13 | `swift build` on Linux would also fail on `AudioSourceAVFoundation` (and on a SwiftUI app target) because SwiftPM builds every target. | manifest | Phase 0 |
| 14 | Server defaults are `--port 8080` / `--binary`; wiki says `7742` / `--mockingbird`. | code vs wiki | C |

**A recipe that fixes #2–#7 was prototyped and scores 60/60 exact** with both the full library
and a major/minor-only library: spectral-peak chroma (local maxima above 2 % of the window
maximum, parabolic interpolation, 65–2000 Hz), energy-weighted cumulative aggregation, Pearson
correlation, and the minor weights `[5, 2, 3.5, 4.5, 2, 4, 2, 4.5, 3.5, 2, 3, 3]`. The exact test
signals are the ones `ToneSynth` in Phase 0 generates, so Track A's acceptance matrix is known to
be reachable.

**Pearson vs cosine, reconciled:** the code and README use cosine; CLAUDE.md and ticket MB-7 say
Pearson. The experiment settles it for Pearson. Code changes (A), README changes (D), CLAUDE.md
was already right.

---

## 2. Definition of finished

1. Core compiles and its tests pass on macOS and Linux; the accuracy matrix in A4 passes.
2. `mockingbird` implements the wiki flag set, decodes WAV/AIFF/M4A on macOS, emits NDJSON or line output.
3. `mockingbird-server` serves `GET /health`, `POST /analyze`, `WS /stream` against the real CLI subprocess, with queueing tested.
4. `MiniAudioSource` and `MiniAudioFileSource` are real, compile on Linux, and are exercised headless through miniaudio's null backend and file decoder. Real device capture on Linux is **not** testable headless and is reported as such.
5. A SwiftUI macOS app (live mic + file drop; key, confidence, alternates) builds as an SPM target and bundles into an ad-hoc-signed `MockingBird.app`.
6. All tests are Swift Testing and pass locally via `./scripts/test.sh`.
7. CI workflow, Makefile, README, CLAUDE.md match reality.

Deliberate non-goals: the MB-16 `MockingBirdError`/`PipelineStage` redesign (the shipped
`PipelineError`/`ErrorContext` shape is what CLAUDE.md documents; exit codes and HTTP statuses
are defined in §4 instead), `.xcodeproj` (no Xcode on this machine; the app is an SPM target),
notarization, iOS.

---

## 3. Phase 0 — integrator, before spawning agents (about 5 minutes)

```sh
cd /Users/bradley/develop/mockingbird
git checkout develop && git status --short          # expect only "?? docs/"
git add docs/plans && git commit -m "docs: [MB-23] add completion plan and Phase 0 contract patch"
git apply --index docs/plans/2026-11-15-phase0-contract.patch
swift build && ./scripts/test.sh                    # expect: Build complete; 4 tests passed
git commit -m "chore: [MB-18] add Phase 0 contract scaffold for parallel tracks"

mkdir -p /Users/bradley/develop/mockingbird-wt
git worktree add /Users/bradley/develop/mockingbird-wt/core   -b feat/core-dsp     develop
git worktree add /Users/bradley/develop/mockingbird-wt/cli    -b feat/cli          develop
git worktree add /Users/bradley/develop/mockingbird-wt/server -b feat/server-linux develop
git worktree add /Users/bradley/develop/mockingbird-wt/app    -b feat/app-docs     develop
```

What the patch does (all of it is interface scaffolding; nothing in it is a track's real work):

- **`Package.swift` in its final form.** New targets `CMiniAudio` (C), `MockingBirdApp`,
  `MockingBirdTestSupport`, and test targets `MockingBirdServerTests`,
  `MockingBirdMiniAudioTests`, `MockingBirdAppTests`. Apple-only targets
  (`AudioSourceAVFoundation`, `MockingBirdApp`, `MockingBirdAppTests`) are appended under
  `#if os(macOS)` so plain `swift build` / `swift test` work on Linux. **No track edits
  `Package.swift`.**
- **Frozen cross-track stubs** with the exact public signatures in §4:
  `ChromaAggregation` + the `aggregation:` parameter on `AnalysisPipeline.init` (stored, not yet
  honoured), `AVFoundationFileSource`, `MiniAudioSource(deviceName:)`,
  `MiniAudioSource.inputDeviceNames()`, `MiniAudioFileSource`, a placeholder SwiftUI `@main`.
- **`Tests/MockingBirdTestSupport`** (complete, shared, frozen): `ToneSynth` (cadences, melodies,
  chords), `SyntheticSource`, `AudioFixture` (raw Float32 and 16-bit WAV bytes, temp files),
  `BuiltProducts.executable("mockingbird")` (finds built binaries; verified under CLT).
- **`scripts/test.sh`**: `swift test` plus the framework/rpath flags Swift Testing needs without Xcode.
- Existing XCTest files wrapped in `#if canImport(XCTest)` so the test graph compiles under CLT
  until Track A migrates them. Placeholder Swift Testing file in each other test target.
- Moves `miniaudio_bridge.h` into the C target, creates `Vendor/miniaudio/`, ignores
  `.build-linux/` and `build/`, removes the tracked `Sources/.DS_Store`.

---

## 4. Cross-track contracts (frozen)

If a track believes a contract here must change, it does **not** change it. It finishes against
the contract as written and lists the request under "Contract change requests" in its report.

### 4.1 Core API (A implements; B and D consume)

```swift
public enum ChromaAggregation: Equatable, Codable, Sendable {
    case perWindow                 // result reflects its own window only
    case cumulative                // result reflects all windows since stream start
    case rolling(windows: Int)     // result reflects the most recent N windows
}

public actor AnalysisPipeline {
    public init(source: any AudioSource,
                config: AudioConfig = AudioConfig(),
                library: ProfileLibrary = .default,
                aggregation: ChromaAggregation = .cumulative) throws
    public func start() throws -> AsyncThrowingStream<KeyResult, Error>   // one result per hop
    public func stop()
}
```

- One `KeyResult` per hop in every mode. With `.cumulative`, the **last** result of a finite
  stream is the result for the whole input; that is how the CLI and app get a single answer.
- `KeyResult.timestamp` = seconds of audio consumed at the end of the analysed window:
  `(windowIndex * hopSize + windowSize) / sampleRate`. Deterministic, not wall-clock.
- `KeyResult.confidence` and each alternate's `confidence` = Pearson r clamped to `[0, 1]`.
  Guide values from the prototype: tonal material 0.79–0.93, white noise about 0.44, silence 0.
- A stream shorter than one window yields zero results and finishes without error.
- Live "rolling" window used by both CLI `--continuous` and the app:
  `.rolling(windows: max(1, Int(15 * sampleRate / Double(hopSize))))` (about 15 s).
- `ProfileLibrary` stays `Codable`; its JSON is `{"profiles":[{"name","root","category","scaleName","weights"}]}` with `root` as a pitch-class string. Decoding validates (12 weights, non-empty) and throws `DecodingError` rather than trapping.

### 4.2 KeyResult JSON (A implements via Codable; B emits; C relays opaque; D does not use)

`JSONEncoder` with `.sortedKeys`, one object per line, no pretty-printing:

```json
{"alternates":[{"category":"pentatonic","confidence":0.881,"key":"C","scaleName":"major pentatonic"}],"category":"major","confidence":0.924,"key":"C","scaleName":"major","timestamp":3.99}
```

`key` is one of `C C# D D# E F F# G G# A A# B` (sharps only). `category` is a `ScaleCategory`
raw value. Decoding `PitchClass` must accept these strings (and may also accept the legacy
integers 0–11).

### 4.3 `mockingbird` CLI (B implements; C spawns it; integrator verifies)

```
mockingbird [options] [<file>]

--sample-rate <int>     default 44100. Rate of raw PCM input, and analysis rate for decoded/device input
--window-size <int>     default 4096, power of two
--hop-size <int>        default 2048, 1...window-size
--alternates <int>      default 3, >= 0
--zero-pad              flag
--profiles <path>       ProfileLibrary JSON (4.1)
--device <name>         capture device by name; "default" = system default input
--continuous            emit a rolling result every hop until input ends or the process is killed
--format json|line      default json
--duration <seconds>    stop after this much audio. Default: none; 10 for device input without --continuous
--list-devices          print capture device names, one per line, exit 0
--file <path>           alias for the positional <file> (kept; the old README documents it)
--help, --version       stdout, exit 0
```

- **Input precedence:** `<file>` > `--device` > stdin when stdin is not a TTY > default device when stdin is a TTY.
- **File type by extension:** `.raw`, `.pcm`, `.f32` → Core `FileSource` (mono Float32 LE at `--sample-rate`). Anything else → `AVFoundationFileSource` on macOS, `MiniAudioFileSource` on Linux (decoded, downmixed to mono, resampled to `--sample-rate`).
- **stdin:** mono Float32 little-endian at `--sample-rate`.
- **Output, stdout only:** without `--continuous`, exactly **one** line when input ends, using `.cumulative`. With `--continuous`, one line per hop using the rolling window from 4.1, flushed after every line.
- **`--format line`:** tab-separated `timestamp(%.2f)`, `key scaleName`, `confidence(%.3f)`, alternates as `key scaleName conf` joined by `"; "`. Example: `3.99<TAB>C major<TAB>0.924<TAB>C major pentatonic 0.881; G mixolydian 0.842`.
- **stderr:** `mockingbird: error: <message>`. Nothing but results ever goes to stdout.
- **Exit codes:** `0` ok · `1` runtime failure (audio source / pipeline error) · `2` usage error (unknown flag, bad value) · `3` input ended before one full window (no result) · `4` input unreadable (file missing or undecodable, profiles file invalid).
- Flag values are validated in the CLI **before** constructing `AudioConfig` (whose preconditions trap).

### 4.4 `mockingbird-server` (C implements; integrator verifies; D documents)

```
--port <int>             default 7742
--host <string>          default 127.0.0.1
--max-connections <int>  default 4
--mockingbird <path>     default: "mockingbird" in the same directory as the server executable
--max-body-bytes <int>   default 104857600
```

| Route | Behaviour |
|---|---|
| `GET /health` | `200`, body `ok` |
| `POST /analyze` | Body is audio. `200 application/json` with the single KeyResult line from the CLI. |
| `WS /stream` | Client sends **binary** frames of mono Float32 LE PCM (any size up to 1 MiB, need not be 4-byte aligned). Server sends one **text** frame per CLI output line (KeyResult JSON). Client sends the text frame `end` to finish: server closes the subprocess's stdin, forwards remaining lines, then closes normally. If the client just disconnects, the subprocess is terminated. |

- **Query parameters** on both routes, all optional, validated as numbers/booleans server-side and passed as argv (never through a shell): `sampleRate`, `windowSize`, `hopSize`, `alternates`, `zeroPad`. `--profiles` and `--device` are never exposed.
- **`POST /analyze` content types:** `application/octet-stream`, `audio/pcm`, or none → raw PCM piped to CLI stdin. `audio/wav|x-wav|wave` → `.wav`, `audio/aiff|x-aiff` → `.aiff`, `audio/mp4|m4a|x-m4a` → `.m4a`, `audio/mpeg` → `.mp3`, `audio/flac` → `.flac`: body written to a temp file with that extension, passed as the positional file, removed afterwards. Anything else → 415.
- **Errors:** `{"error":{"code":"<code>","message":"<text>"}}`.
  `400 invalid_parameter` · `400 empty_body` · `413 payload_too_large` · `415 unsupported_media_type` · `422 insufficient_audio` (CLI exit 3) · `422 undecodable_audio` (CLI exit 4) · `500 analysis_failed` (other non-zero exit; message carries CLI stderr) · `500 spawn_failed`.
  On `/stream`, a failure is sent as one text frame with the same error object, then close code 1011.
- **Pool:** at most `maxConnections` subprocesses alive. Extra requests and sockets wait (never rejected); a WebSocket is upgraded immediately and its frames are simply not read until it holds a slot. One fresh process per request/connection; the slot is released when the process has exited.
- The server does not link `MockingBirdCore` and never parses KeyResult.

### 4.5 Audio source types (B and C implement; B's CLI and D's app consume)

```swift
// AudioSourceAVFoundation (macOS) — Track B
public final class AVFoundationSource: AudioSource { public init(deviceName: String? = nil); public static func inputDeviceNames() -> [String] }
public struct AVFoundationFileSource: AudioSource { public init(url: URL) }

// AudioSourceMiniAudio (Linux, also builds on macOS) — Track C
public final class MiniAudioSource: AudioSource { public init(deviceName: String? = nil); public static func inputDeviceNames() throws -> [String] }
public struct MiniAudioFileSource: AudioSource { public init(url: URL) }
```

`AVFoundationSource()` with no arguments keeps working (the app uses it). File sources finish
the stream at end of file; a missing or undecodable file makes `start` throw or the stream fail
with an `AudioSourceError`. The app requests microphone permission itself with
`AVCaptureDevice.requestAccess(for: .audio)`; it does not need a helper from Track B.

---

## 5. Rules for every track

- Work only in your worktree, only in files you own (§6). **Frozen for everyone:**
  `Package.swift`, `Package.resolved`, `Tests/MockingBirdTestSupport/**`, `scripts/test.sh`,
  `docs/plans/**`. Need more test helpers? Add a file in your own test directory.
- Read `CLAUDE.md` first. Hard rules that bite here: no Apple frameworks in Core (see A1 for the
  one guarded exception); no `DispatchQueue`, `Thread`, or `pthread` in new Swift; typed errors
  at module boundaries; no `!`, `try!`, `fatalError` in production paths; one primary type per
  file; models in their own files, apart from the logic that uses them; no `print()` (write
  results through `FileHandle.standardOutput`, diagnostics through a small logging type or
  swift-log); `mb_` prefix and checked return values in C.
- TDD: write the failing test, run it and see it fail for the right reason, implement, see it
  pass, commit. Tests are Swift Testing (`import Testing`, `@Test`, `#expect`, `#require`). No XCTest.
- Run tests with `./scripts/test.sh` (optionally `--filter <TargetName>`). Plain `swift test`
  fails on this machine because only Command Line Tools are installed.
- Commits: `<type>: [MB-N] <subject>`, imperative, subject at most 72 characters, body explains
  why. End every commit message with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
  Ticket numbers: existing MB-2…MB-17 as named per task; new ones the integrator will create:
  **MB-18** Swift Testing migration and test infrastructure · **MB-19** CLI interface ·
  **MB-20** audio file decoding · **MB-21** chroma aggregation and detection accuracy ·
  **MB-22** SwiftUI app and bundle · **MB-23** build, CI, docs.
- No `git push`, no PRs, no Notion edits, no merging other tracks into your branch.
- Do not start live microphone capture (it raises a macOS permission prompt on Bradley's
  machine). Anything needing the mic is listed as a manual check.
- Finish with a report: commits made, the acceptance commands you ran with their actual output
  tails, anything not verified and why, and "Contract change requests" (or "none").

---

## 6. File ownership (disjoint)

| Track | Branch / worktree | Owns |
|---|---|---|
| **A Core** | `feat/core-dsp` · `mockingbird-wt/core` | `Sources/MockingBirdCore/**`, `Tests/MockingBirdCoreTests/**` |
| **B CLI** | `feat/cli` · `mockingbird-wt/cli` | `Sources/MockingBirdCLI/**`, `Sources/AudioSourceAVFoundation/**`, `Tests/MockingBirdCLITests/**` |
| **C Server + Linux** | `feat/server-linux` · `mockingbird-wt/server` | `Sources/MockingBirdServer/**`, `Sources/AudioSourceMiniAudio/**`, `Sources/CMiniAudio/**`, `Vendor/miniaudio/**`, `Tests/MockingBirdServerTests/**`, `Tests/MockingBirdMiniAudioTests/**`, `scripts/linux.sh` |
| **D App + build + docs** | `feat/app-docs` · `mockingbird-wt/app` | `Sources/MockingBirdApp/**`, `Tests/MockingBirdAppTests/**`, `Support/MockingBirdApp/**`, `scripts/bundle-app.sh`, `Makefile`, `.github/workflows/ci.yml`, `README.md`, `CLAUDE.md`, `.gitignore` |

---

## 7. Track A — Core correctness

**Goal:** Core compiles on Linux, detects keys accurately on synthetic signals, aggregates
chroma across windows, and has a real Swift Testing suite.

### A1 · Linux portability (do this first; Track C's Linux check depends on it) — `[MB-14]`
- Remove `import Accelerate` from `ChromaExtractor` and `KeyDetector`; 12-element arithmetic in plain Swift.
- Add `DSP/FFT/RadixTwoFFT.swift`: pure-Swift iterative radix-2 FFT, always compiled, returning magnitudes on the same scale as the vDSP path.
- `FFTProcessor` uses vDSP under `#if canImport(Accelerate)` and `RadixTwoFFT` otherwise. This is the single sanctioned Apple import in Core; Track D records the exception in CLAUDE.md.
- Tests (`RadixTwoFFTTests`): impulse → flat spectrum; 440 Hz sine → peak at the expected bin; on macOS, `RadixTwoFFT` and the vDSP path agree within 1e-3 relative for bins 1…N/2-1 on a multi-tone signal.
- **Check:** `./scripts/test.sh --filter MockingBirdCoreTests` passes. Then
  `docker run --rm -v "$PWD":/src -v mockingbird-linux-build:/build -w /src swift:6.2 swift build --scratch-path /build --target MockingBirdCore` → `Build of target: 'MockingBirdCore' complete!`
  and `grep -rn "^import" Sources/MockingBirdCore | grep -v -E "Foundation|Accelerate"` prints nothing, with every `import Accelerate` line sitting inside `#if canImport(Accelerate)`.
- Commit this as soon as it is green so `feat/core-dsp` carries it early.

### A2 · Migrate tests to Swift Testing — `[MB-18]`
- Rewrite the five files in `Tests/MockingBirdCoreTests` with `import Testing`; delete the `#if canImport(XCTest)` guards and the local `SyntheticSource` (use `MockingBirdTestSupport`).
- The two existing pipeline tests feed simultaneous 7-note clusters, which a 4096 window cannot resolve; replace them in A4 rather than porting them.
- **Check:** `grep -rn XCTest Tests/MockingBirdCoreTests` prints nothing; suite passes.

### A3 · Models and structural tests — `[MB-2]`, `[MB-15]`, `[MB-5]`
- `PitchClass` Codable as the strings in §4.2 (decode strings; integers 0–11 optional). Remove the `!` in `transposed(by:)`.
- Golden test: a fixed `KeyResult` encodes with `.sortedKeys` to exactly the §4.2 shape and round-trips. Round-trip tests for `ChromaVector`, `AudioConfig`, `ScaleProfile`, `ProfileLibrary`, `ChromaAggregation`, `PipelineError`.
- `AudioConfig` defaults test (44100 / 4096 / 2048 / 3 / false); `PitchClass` has 12 sharps-only cases; `ScaleCategory` cases.
- `ProfileLibrary.profiles(for: ScaleCategory)` and `profiles(for: PitchClass)` (MB-5). Validating `init(from:)` on `ScaleProfile`/`ProfileLibrary`: 12 weights, non-empty, else `DecodingError` (test with bad JSON).

### A4 · Accuracy: spectral-peak chroma, Pearson, minor profile — `[MB-4]`, `[MB-7]`, `[MB-6]`
Write the matrix test first (`KeyDetectionAccuracyTests`), parameterised over roots 0…11 with
`root = 48 + r` and default `AudioConfig`, detecting on the **last** result of a `.cumulative`
pipeline fed by `SyntheticSource`:

| Signal (`ToneSynth`) | Expected with `ProfileLibrary.default` |
|---|---|
| `majorCadence(root:)` | exactly `<root> major` |
| `minorCadence(root:)` | exactly `<root> minor` |
| `minorCadence(root:, harmonicDominant: true)` | exactly `<root> minor` |
| `scaleMelody(root:, minor: false)` | exactly `<root> major` |
| `scaleMelody(root:, minor: true)` | exactly `<root> minor` |

That is 60 cases; all must pass. Further tests:
- Same matrix at `sampleRate: 48000`, at `windowSize: 8192, hopSize: 4096`, and with `zeroPad: true`: at least 57/60 each (report the actual numbers).
- Single tones at MIDI 40, 45, 52, 57, 60, 69, 81: the chroma peak is the right pitch class (today 40 → F).
- A lone major triad: `key` is the root and `<root> major` is the winner or among 3 alternates.
- Tonal confidence ≥ 0.75 on every matrix case; white noise (seeded generator) < 0.6; all-zero input → confidence 0 and no crash, no NaN.
- Confidence and alternates are in `[0, 1]`, alternates sorted descending, count ≤ `numAlternates`.

Then implement, following the prototyped recipe unless you find something better that still
passes everything:
- `ChromaExtractor`: only spectral peaks contribute (local maxima above 2 % of the window's maximum magnitude, parabolic interpolation on log magnitude for the peak frequency, 65–2000 Hz, add the peak magnitude to its pitch class). Keep `extract(_:) -> ChromaVector` L2-normalised and add an un-normalised path for aggregation (for example `extractEnergy(_:) -> [Float]`), so loud windows count for more.
- `KeyDetector`: Pearson correlation; confidence = r clamped to `[0, 1]` for winner and alternates. Delete the min-max rescale. Update the doc comments (they argue for cosine).
- `ProfileLibrary`: minor weights → `[5, 2, 3.5, 4.5, 2, 4, 2, 4.5, 3.5, 2, 3, 3]` (covers natural and harmonic minor). Add **bebop dominant** and **bebop major** (MB-6, category `.jazz`), keeping the existing jazz minor: 16 scale types x 12 = 192 profiles. If bebop cannot be added without breaking the matrix, leave it out and report that. Update `ProfileLibraryTests` (12 transpositions each, unit norm, count).
- **Check:** `./scripts/test.sh --filter MockingBirdCoreTests` passes, including 60/60.

### A5 · FFT correctness — `[MB-3]`
- Test: with `zeroPad: true`, processing the same window twice gives identical output, and a 440 Hz sine peaks at the expected bin of the doubled FFT. Fix by clearing the padded region each call.
- Remove the `baseAddress!` force unwraps.

### A6 · Pipeline aggregation and timestamps — `[MB-9]`, `[MB-21]`
- New `Pipeline/ChromaAccumulator.swift` (value type) implementing `.perWindow`, `.cumulative`, `.rolling(windows:)` over un-normalised chroma.
- `AnalysisPipeline` honours `aggregation`; timestamps per §4.1; cancel the reader task when the consumer stops iterating or `stop()` is called; no `!`.
- Tests: result count for an N-sample stream is `floor((N - windowSize) / hopSize) + 1`; timestamps follow the formula exactly; chunk size (1, 1000, 4096, 10000) does not change results; a stream shorter than one window yields nothing; `.rolling(windows: 20)` on C-major cadence followed by F#-major cadence ends on F# major while `.cumulative` still reports from both; `.perWindow` matches direct `detect(extract(process(window)))`.

### A7 · Data sources — `[MB-12]`
- `RawPCMSource`: carry leftover bytes between reads so samples stay aligned (test with a `Pipe` written in 3-, 5- and 7-byte pieces). Decode explicitly as little-endian.
- `FileSource`: read in chunks instead of loading the whole file, honour `stop()`, and throw a typed `AudioSourceError` for a missing file (test with a temp file from `AudioFixture.rawFloat32`).

### A8 · Linux test run
`docker run --rm -v "$PWD":/src -v mockingbird-linux-build:/build -w /src swift:6.2 swift test --scratch-path /build --filter MockingBirdCoreTests`
Expected: passes. (Other targets may not compile on Linux until the tracks merge; if the whole
test graph fails to build for reasons outside Core, report the errors and fall back to the
`swift build --target MockingBirdCore` check.) Note in your report whether
`BuiltProducts` (uses `dladdr`) compiled on Linux.

---

## 8. Track B — CLI and AVFoundation sources

**Goal:** the §4.3 contract, real file decoding and device selection on macOS, and integration
tests that run the built binary.

Before the tracks merge your binary links Phase-0 Core (per-window results, integer `key`,
wall-clock timestamps). Write tests that hold both before and after the merge: decode stdout
with `JSONDecoder().decode(KeyResult.self, …)` instead of string-matching `key`, and assert
only the **root** (`key == .c`) for key correctness. Exact-scale accuracy is Track A's job and
is re-checked at integration.

### B1 · Options model and parser — `[MB-19]`
- `CLIOptions` (model), `CLIOptionsParser` (logic), `CLIUsageError` (typed, `Error`), `OutputFormat`, `InputSelection` — one type per file under `Sources/MockingBirdCLI/`. Hand-rolled parser; no new dependency.
- Unit tests via `@testable import MockingBirdCLI`: defaults; every flag; positional file and `--file`; unknown flag; missing value; non-numeric value; window size not a power of two; hop > window; negative alternates; `--format xml`; two positional files. Each bad case yields a `CLIUsageError` with a message naming the flag.

### B2 · Output formatting — `[MB-19]`
- `ResultFormatter`: `.json` (sorted keys, single line) and `.line` (§4.3). Unit tests with a fixed `KeyResult`; the line test asserts the exact string.
- `ResultWriter` writes to `FileHandle.standardOutput` and flushes per line. No `print()`.

### B3 · Main flow and exit codes — `[MB-19]`
- `MockingBirdCLI.main`: parse → select input (§4.3 precedence) → build `AudioConfig` and library (`--profiles`) → pipeline (`.cumulative`, or rolling when `--continuous`) → emit → exit code. `--duration` stops the pipeline once `result.timestamp >= duration`.
- Integration tests (`CLIProcessTests`, running `BuiltProducts.executable("mockingbird")` with `Process`):
  - raw C-major cadence on stdin → exit 0, exactly one stdout line, decodes, `key == .c`, stderr empty;
  - same with `--continuous` → more than 50 lines, timestamps non-decreasing;
  - `--format line` → one line with 4 tab-separated fields;
  - `--alternates 1` → one alternate; `--alternates 0` → none;
  - empty stdin (`/dev/null`) → exit 3, stdout empty, stderr starts `mockingbird: error:`;
  - `--window-size 1000` → exit 2; unknown flag → exit 2; missing file → exit 4; malformed `--profiles` → exit 4;
  - `--profiles` with a library containing only C major and G major → result is one of those two;
  - `--help` → exit 0 with every flag from §4.3 in stdout; `--version` → exit 0;
  - `.raw` positional file gives the same result as the same bytes on stdin.

### B4 · File decoding — `[MB-20]`
- Implement `AVFoundationFileSource` with `AVAudioFile` + `AVAudioConverter`: any channel count → mono, any rate → requested rate, Float32, delivered in chunks, stream finishes at EOF, `stop()` cancels. Missing/undecodable file → typed `AudioSourceError`; the CLI maps that to exit 4.
- Tests (macOS): write a cadence with `AudioFixture.wav16` and run `mockingbird file.wav` → exit 0, `key == .c`. Convert the WAV with `/usr/bin/afconvert` to AIFF (`-f AIFF -d BEI16`) and M4A (`-f m4af -d aac`) and assert the same root. A 22050 Hz WAV and a stereo WAV (build stereo with `afconvert -c 2`) give the same root. A text file renamed `.wav` → exit 4.
- Direct unit test of the source: total samples delivered for a 4 s 44.1 kHz WAV is within 1 % of 176400, and of 192000 when asked for 48000.

### B5 · Microphone and device selection — `[MB-10]`
- `AVFoundationSource(deviceName:)`: resolve the name to a CoreAudio input device and set it on the engine's input unit; `"default"`/`nil` → system default; unknown name → `.deviceUnavailable`. Authorisation status `.denied`/`.restricted` → `.permissionDenied`.
- Build the `AVAudioConverter` and output buffer once at `start`, not inside every tap callback.
- `inputDeviceNames()` and `--list-devices`.
- Tests that need no capture: `--list-devices` exits 0; `--device "no-such-device-xyz"` exits 1 with a message naming the device (device lookup must fail before any capture starts, so no permission prompt appears).
- **Manual (Bradley):** `mockingbird --device default --duration 5` and `--continuous` against real audio.

### B6 · Final check
`swift build && ./scripts/test.sh --filter MockingBirdCLITests` passes;
`grep -rn "print(" Sources/MockingBirdCLI Sources/AudioSourceAVFoundation` prints nothing.

---

## 9. Track C — Server, miniaudio, Linux

**Goal:** the §4.4 contract against the real CLI, real miniaudio sources, Linux compile proof.

### C1 · Options and application skeleton — `[MB-17]`
- `ServerOptions` + `ServerOptionsParser` (typed usage error, exit 2). Defaults per §4.4; resolve the co-located `mockingbird` from the server executable's own location. Remove `--binary`.
- `ApplicationBuilder` returns the Hummingbird application for given options so tests can run it with `HummingbirdTesting` (`.live`, ephemeral port). `main` only parses and runs.
- Ignore `SIGPIPE` at startup (`signal(SIGPIPE, SIG_IGN)`): a subprocess that exits early must not kill the server on the next stdin write.
- Tests: parser cases; `GET /health` → 200 `ok`.

### C2 · Process pool — `[MB-17]`
- `ProcessPool` actor: slot accounting with FIFO waiters; the slot is held for the life of the subprocess and released after exit, on every path including errors and cancellation.
- `MockingbirdProcess`: spawns the binary with argv, exposes stdin writes, an async sequence of stdout lines, collected stderr, and exit status. Bridge `readabilityHandler`/`terminationHandler` into `AsyncStream`/continuations; `FileHandle.bytes` is not available on Linux, and `DispatchQueue`/`Thread` are not allowed.
- Tests with a fake binary (a shell script written to a temp dir that logs start/end timestamps to a file, sleeps 0.3 s, drains stdin, prints one JSON line): with `maxConnections = 1` and 4 concurrent jobs all succeed and the logged intervals never overlap; with `maxConnections = 2` at most two overlap; a job whose binary path does not exist fails with `spawn_failed` and the next job still runs (slot released).

### C3 · `POST /analyze` — `[MB-17]`
- Parameter validation → argv; raw bodies piped to stdin while stdout is read concurrently; encoded bodies via temp file (always removed); exit-code → status mapping per §4.4.
- Tests against the real CLI (`BuiltProducts.executable("mockingbird")`, passed as `--mockingbird`): raw cadence → 200, `Content-Type: application/json`, body is one JSON object with a `key` field; WAV body with `audio/wav` → 200; empty body → 400 `empty_body`; `windowSize=1000` → 400 `invalid_parameter`; `text/plain` → 415; 100 samples of raw audio → 422 `insufficient_audio`; garbage with `audio/wav` → 422 `undecodable_audio`; body over `--max-body-bytes` → 413; six concurrent requests with `maxConnections = 2` → six 200s. Assert the temp directory holds no leftover files afterwards.
- Do not assert on the value of `key` beyond its presence (Core accuracy lands with Track A).

### C4 · `WS /stream` — `[MB-17]`
- Upgrade, acquire slot, spawn `mockingbird --continuous --format json …`, pump binary frames to stdin, forward each stdout line as a text frame, `end` handling, disconnect → terminate subprocess, error frame + 1011 on failure. Max frame size 1 MiB.
- Tests with `HummingbirdWSClient` against the real CLI: send a 4 s cadence in 16384-byte binary frames then `end` → receive at least 50 text frames, each parses as JSON with a `key`, then a normal close; with `maxConnections = 1`, a second socket receives its frames only after the first finishes, and both complete; client that disconnects mid-stream leaves no `mockingbird` child (the pool reports zero active slots shortly after); bad query parameter → error frame then close.

### C5 · Vendor miniaudio and the C bridge — `[MB-11]`
- Download the latest tagged `miniaudio.h` release from github.com/mackron/miniaudio into `Vendor/miniaudio/`, with `VERSION` (tag, URL, sha256) and its licence text. Remove `.gitkeep`. Commit as `chore: [MB-11] vendor miniaudio <version>`.
- `Sources/CMiniAudio`: `miniaudio_bridge.c` defines `MINIAUDIO_IMPLEMENTATION` (put any `MA_NO_*` defines here, since `Package.swift` is frozen) and the `mb_` API: context/device init for capture (mono, f32, requested rate, by device name or default, backend selectable so tests can force the null backend), start, stop, uninit, device enumeration, a read function, and decoder open/read/close. Every `ma_result` is checked and returned.
- **Real-time rule:** the miniaudio data callback only writes into a lock-free ring buffer (`ma_pcm_rb`) allocated at init. No allocation, locks, or Swift in the callback.
- Replace the Phase 0 placeholder function; keep the header name `miniaudio_bridge.h`.

### C6 · `MiniAudioSource` and `MiniAudioFileSource` — `[MB-11]`, `[MB-20]`
- `MiniAudioSource`: a Swift `Task` drains the ring buffer on a short `Task.sleep` cadence and yields chunks; `stop()` stops the device and finishes the stream. Add an internal initialiser that forces the null backend for tests; the public API stays as in §4.5.
- `MiniAudioFileSource`: miniaudio decoder configured for mono f32 at the requested rate (WAV, FLAC, MP3).
- Tests (`MockingBirdMiniAudioTests`, same on macOS and Linux): null-backend source delivers at least 0.5 s of samples within 2 s of wall time and finishes after `stop()`; unknown device name → `.deviceUnavailable`; file source on an `AudioFixture.wav16` cadence delivers 176400 ± 1 % samples, and those samples through `AnalysisPipeline` give `key == .c`; resampling to 48000 gives 192000 ± 1 %; missing file and garbage file → typed error.
- **Not testable headless:** capture from a real ALSA/PipeWire device. Say so in the report.

### C7 · Linux verification — `[MB-14]`
- `scripts/linux.sh <build|test|shell> [args…]`: runs `swift:6.2` with the repo mounted at `/src` and a named volume (`mockingbird-linux-build`) as `--scratch-path /build`.
- On your own branch: `./scripts/linux.sh build --target CMiniAudio` and `--target MockingBirdServer` must succeed.
- Full Linux proof needs Track A's A1 commit. Check `git log feat/core-dsp --oneline | grep "MB-14"`. If present, make a throwaway worktree
  (`git worktree add ../linux-verify -b verify/linux HEAD && cd ../linux-verify && git merge --no-edit feat/core-dsp`), run `./scripts/linux.sh build` then `./scripts/linux.sh test --filter MockingBirdMiniAudioTests` and `--filter MockingBirdServerTests`, record the output, then remove the worktree and branch. Do not merge into `feat/server-linux`. If A1 is not there yet, say so; the integrator runs it in §11.

### C8 · Final check
`swift build && ./scripts/test.sh --filter MockingBirdServerTests && ./scripts/test.sh --filter MockingBirdMiniAudioTests` pass;
`grep -rn "MockingBirdCore" Sources/MockingBirdServer` prints nothing;
`grep -rn -E "DispatchQueue|Thread\b|print\(" Sources/MockingBirdServer Sources/AudioSourceMiniAudio` prints nothing.

---

## 10. Track D — macOS app, bundling, Makefile, CI, docs

**Goal:** a working SwiftUI app as an SPM target and `.app` bundle, plus build tooling and
documentation that describe the finished system (use §4 as the source of truth for what the
other tracks deliver).

### D1 · View model — `[MB-22]`
- `KeyDetectionViewModel` (`@MainActor`, `@Observable`): state `idle | requestingPermission | listening | analyzingFile(name) | finished(name) | failed(message)`, plus `result: KeyResult?`. Dependencies injected as closures so tests need no hardware: live-source factory, file-source factory, permission request.
- Listening uses `AnalysisPipeline(..., aggregation: .rolling(…))` per §4.1 and publishes each result; file analysis uses `.cumulative` and publishes the last result. Starting one mode stops the other. Permission denied → `failed` with a message pointing at System Settings.
- The app **never starts the microphone at launch**; only when the user presses Listen.
- Tests (`MockingBirdAppTests`, `SyntheticSource` + `ToneSynth`): file analysis of a C-major cadence ends `finished` with `result.key == .c`; listening publishes results and `stop()` returns to `idle`; denied permission → `failed`; a failing source → `failed` with its description; a file with under one window of audio → `failed` ("not enough audio"); starting file analysis while listening stops listening.

### D2 · Views — `[MB-22]`
- `MockingBirdApp` (scene), `ContentView`, `KeyDisplayView` (large key + scale name, confidence bar, shows a muted "Listening…" state while `confidence < 0.6`), `AlternatesView`, `DropZoneView` (`.onDrop` of file URLs plus an Open… button via `.fileImporter`), Listen/Stop button. One view per file. Native controls, light and dark both legible.
- Real sources are wired only in the app entry point: `AVFoundationSource()`, `AVFoundationFileSource(url:)`, `AVCaptureDevice.requestAccess(for: .audio)`.
- If the first command-line argument is an existing file path, analyse it at launch (lets `open MockingBird.app --args song.wav` work and gives the integrator a scripted smoke path).
- **Check:** `swift build --product MockingBirdApp` succeeds.

### D3 · Bundle — `[MB-22]`
- `Support/MockingBirdApp/Info.plist`: `CFBundleExecutable` `MockingBird`, `CFBundleIdentifier` `es.bradleybarn.mockingbird` (Bradley to confirm), `CFBundlePackageType` `APPL`, `CFBundleShortVersionString`, `LSMinimumSystemVersion` `14.0`, `NSHighResolutionCapable`, `NSMicrophoneUsageDescription`.
- `scripts/bundle-app.sh`: release build of the product, assemble `build/MockingBird.app/Contents/{MacOS,Resources}`, copy plist, `codesign --force --sign -` (ad-hoc), `codesign --verify`.
- **Check:** `./scripts/bundle-app.sh && plutil -lint build/MockingBird.app/Contents/Info.plist && codesign --verify --verbose build/MockingBird.app && /usr/libexec/PlistBuddy -c "Print :NSMicrophoneUsageDescription" build/MockingBird.app/Contents/Info.plist` all succeed.
- Launch smoke (once): `open build/MockingBird.app; sleep 4; pgrep -x MockingBird && osascript -e 'quit app "MockingBird"'` → a PID is printed. Do not press Listen.

### D4 · Makefile — `[MB-23]`
Targets: `build`, `build-release`, `test` (`./scripts/test.sh`), `test-core|cli|server|app` (filters), `linux-build` and `linux-test` (`./scripts/linux.sh build|test`, Track C's script), `app` (`./scripts/bundle-app.sh`), `run-app` (`open build/MockingBird.app`), `clean` (also removes `build/`), `help`. Remove the Xcode requirement from the header.
**Check:** `make build && make test && make app` succeed in your worktree (`linux-*` will not work until the merge; that is expected).

### D5 · CI — `[MB-23]`
- macOS job: a runner/Xcode that ships **Swift 6.2 or newer** (the pinned dependencies require it; Xcode 16.3 does not qualify). Steps: `swift build`, `swift test`, `./scripts/bundle-app.sh`, `plutil -lint`.
- Linux job: `ubuntu-latest` with `container: swift:6.2`: `swift build`, `swift test`.
- You cannot run Actions locally. Validate the YAML parses (`python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci.yml'))"` or `ruby -ryaml`), and say in your report that the workflow is unexecuted.

### D6 · README and CLAUDE.md — `[MB-23]`
- README: architecture (app is an SPM target, no `.xcodeproj`); DSP pipeline as it now is (spectral-peak chroma, aggregation modes, **Pearson** with the measured reason: cosine scored noise 0.95 and always chose pentatonic); the `PitchClass` JSON form; CLI usage, flags, exit codes, formats (§4.3); server flags, routes, content types, errors, WebSocket protocol (§4.4); audio source table with real status; profile count 192 (16 x 12, including bebop dominant and bebop major — if Track A reports it left bebop out, the integrator adjusts this line); build/test instructions for both Xcode and Command Line Tools (`./scripts/test.sh`), Linux via Docker, `make app`; requirement Swift 6.2+; known limits (accuracy verified on synthetic signals only; live capture needs mic permission; Linux device capture untested headless).
- CLAUDE.md: targets table (add `CMiniAudio`, `MockingBirdApp`, `MockingBirdTestSupport`; replace `MockingBird.xcodeproj`); invariant 1 reworded to allow exactly `import Accelerate` inside `#if canImport(Accelerate)` in `FFTProcessor` with the pure-Swift fallback; key-types block (add `ChromaAggregation`, `ChromaAccumulator`, `RadixTwoFFT`, update `ChromaExtractor`/`KeyDetector`/`KeyResult.timestamp` descriptions); directory layout; a "Testing" section (Swift Testing only, `./scripts/test.sh`, `MockingBirdTestSupport`); sprint section updated.
- **Check:** every command quoted in README exists in the Makefile or §4; `grep -n -i "cosine" README.md CLAUDE.md` shows only the historical explanation; `grep -n "xcodeproj\|8080\|--binary" README.md CLAUDE.md` prints nothing.

### D7 · Final check
`swift build && ./scripts/test.sh --filter MockingBirdAppTests && make app` succeed.

---

## 11. Integration (integrator)

### Merge order
Ownership is disjoint, so merges should be conflict-free in any order; this order makes each
step meaningful to test:

```sh
cd /Users/bradley/develop/mockingbird && git checkout develop
git merge --no-ff feat/core-dsp      && swift build && ./scripts/test.sh
git merge --no-ff feat/cli           && swift build && ./scripts/test.sh
git merge --no-ff feat/server-linux  && swift build && ./scripts/test.sh
git merge --no-ff feat/app-docs      && swift build && ./scripts/test.sh
```

Before merging, read each report's "Contract change requests", and check nobody touched a
frozen file: `git diff develop...feat/<branch> --stat -- Package.swift Package.resolved Tests/MockingBirdTestSupport scripts/test.sh` must be empty for all four.

### Full verification after the last merge

```sh
cd /Users/bradley/develop/mockingbird
T=/tmp/mockingbird-verify && rm -rf $T && mkdir -p $T

# 1. Build and test, macOS
swift build 2>&1 | tail -1                       # Build complete!
./scripts/test.sh 2>&1 | tail -3                 # Test run with N tests ... passed
grep -rn "XCTest" Tests ; grep -rn "TODO: MB-" Sources   # both print nothing

# 2. Linux
./scripts/linux.sh build 2>&1 | tail -1          # Build complete!
./scripts/linux.sh test  2>&1 | tail -3          # passed

# 3. CLI on generated audio (C major I-IV-V-I)
W='2*PI*t'
ffmpeg -hide_banner -loglevel error -y -f lavfi -i "aevalsrc='0.25*if(lt(t,1),sin(261.63*$W)+sin(329.63*$W)+sin(392.00*$W),if(lt(t,2),sin(349.23*$W)+sin(440.00*$W)+sin(523.25*$W),if(lt(t,3),sin(392.00*$W)+sin(493.88*$W)+sin(587.33*$W),sin(261.63*$W)+sin(329.63*$W)+sin(392.00*$W))))':s=44100:d=4" -ac 1 -c:a pcm_s16le $T/cmajor.wav
afconvert -f m4af -d aac   $T/cmajor.wav $T/cmajor.m4a
afconvert -f AIFF -d BEI16 $T/cmajor.wav $T/cmajor.aiff
ffmpeg -hide_banner -loglevel error -y -i $T/cmajor.wav -f f32le -ac 1 -ar 44100 $T/cmajor.raw
MB=.build/debug/mockingbird
for f in wav m4a aiff raw; do $MB $T/cmajor.$f; done        # 4 lines, each "key":"C","scaleName":"major", timestamp ~3.9
$MB < $T/cmajor.raw                                          # same
$MB --format line $T/cmajor.wav                              # 3.9x <TAB> C major <TAB> 0.9xx <TAB> alternates
$MB --continuous $T/cmajor.wav | wc -l                       # about 85
$MB < /dev/null; echo "exit=$?"                              # stderr message, exit=3
$MB --window-size 1000 $T/cmajor.wav; echo "exit=$?"         # exit=2
$MB --list-devices                                           # device names

# 4. Server
.build/debug/mockingbird-server --max-connections 2 & SRV=$!; sleep 1
curl -s localhost:7742/health                                                    # ok
curl -s -X POST --data-binary @$T/cmajor.raw -H 'Content-Type: application/octet-stream' localhost:7742/analyze   # KeyResult, C major
curl -s -X POST --data-binary @$T/cmajor.wav -H 'Content-Type: audio/wav' 'localhost:7742/analyze?alternates=1'  # one alternate
curl -s -o /dev/null -w '%{http_code}\n' -X POST -H 'Content-Type: text/plain' -d x localhost:7742/analyze      # 415
for i in 1 2 3 4 5 6; do curl -s -o /dev/null -w '%{http_code} ' -X POST -H 'Content-Type: application/octet-stream' --data-binary @$T/cmajor.raw localhost:7742/analyze & done; wait; echo   # six 200s

cat > $T/ws.py <<'EOF'
import asyncio, sys, websockets
async def main(path):
    data = open(path, "rb").read()
    async with websockets.connect("ws://127.0.0.1:7742/stream", max_size=None) as ws:
        for i in range(0, len(data), 16384):
            await ws.send(data[i:i + 16384])
        await ws.send("end")
        frames = [m async for m in ws]
    print(len(frames), "frames; last:", frames[-1])
asyncio.run(main(sys.argv[1]))
EOF
uv run --with websockets python $T/ws.py $T/cmajor.raw       # ~85 frames; last has "key":"C","scaleName":"major"
kill $SRV; sleep 1; pgrep -x mockingbird || echo "no orphan subprocesses"

# 5. App
make app
plutil -lint build/MockingBird.app/Contents/Info.plist && codesign --verify --verbose build/MockingBird.app
open build/MockingBird.app --args $T/cmajor.wav; sleep 5; pgrep -x MockingBird   # PID; window shows C major
osascript -e 'quit app "MockingBird"'
```

Then, with Bradley at the keyboard (permission prompts): press Listen in the app and play
music; `mockingbird --device default --duration 5`; drop an m4a onto the app window.

Clean-up once merged: `git worktree remove` the four worktrees, delete the `feat/*` branches,
`docker volume rm mockingbird-linux-build mb-linux-build` if no longer wanted.

---

## 12. Risks and things that need Bradley

1. **Phase 0 is a commit by the integrator, not by a track.** It was the only way found to keep `Package.swift` single-owner and let B, C and D compile against interfaces A/B/C have not written yet. Review the patch before applying; it is 850 lines, mostly test support and the manifest.
2. **Contract change in CLAUDE.md invariant 1.** Keeping vDSP means one guarded `import Accelerate` in Core. If Bradley wants the rule literal, delete the vDSP branch in `FFTProcessor` and use `RadixTwoFFT` everywhere (a one-file change after A lands).
3. **Accuracy is proven on synthetic signals only** (sines with harmonics, cadences, scale melodies). Real recordings, with percussion, inharmonic timbres, tuning offsets and modulation, are untested. The 15 s rolling window and the 0.6 "unsure" threshold are educated defaults.
4. **Modes are distinguished only by tonic emphasis.** C major, D dorian and A minor share pitch classes; the full 192-profile library will sometimes name a relative mode on real music. `--profiles` with a major/minor-only library is the escape hatch.
5. **Microphone permission** cannot be granted by an agent. Live capture in the CLI (attributed to the terminal app) and in the app needs Bradley to click Allow. With ad-hoc signing, macOS may ask again after each rebuild because the code hash changes.
6. **Signing.** Ad-hoc only; fine locally, not distributable. Developer ID, hardened runtime (which then needs the `com.apple.security.device.audio-input` entitlement) and notarization are out of scope. Bundle identifier `es.bradleybarn.mockingbird` is a guess.
7. **CI is unverified** (no pushing). The macOS runner must provide Swift 6.2+; the label and Xcode version Track D picks need confirming on the first real run. The existing workflow is very likely already red for this reason.
8. **Linux device capture is untested.** Docker has no audio device; only the null backend and file decoding run. The pre-merge Linux check for Track C depends on Track A's first commit; otherwise it happens at integration.
9. **`BuiltProducts` on Linux** uses `dladdr(#dsohandle)`; verified on macOS under CLT only. If it fails to compile or locate binaries in the container, set `MOCKINGBIRD_BIN_DIR` in `scripts/linux.sh` (Track C) as the workaround and report it.
10. **Tests written before the merge assert less than they could** (B and C check only that a key is present / the root is right). The §11 run is where exact "C major" through CLI and server is confirmed.
11. **Server has no request timeout.** A stalled subprocess holds a pool slot until its client disconnects. Acceptable for a local gateway; note it if this is ever exposed.
12. **Track C is the largest** (server plus miniaudio plus Docker). If it runs long, C5–C6 (miniaudio) can be split off without touching any other track's files.
13. **Four worktrees each build Hummingbird from scratch** (about 70 s each, a few GB of `.build` in total), and Docker builds add a volume. Tests that open sockets use ephemeral ports, so parallel runs do not collide; only the §11 manual run uses 7742.
14. **Notion tickets MB-1…MB-17 are all still Todo/In Progress** and MB-18…MB-23 do not exist yet; commit messages reference them ahead of creation.
