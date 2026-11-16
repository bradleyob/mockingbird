# MockingBird — Claude Code Contract

## Project Overview
A macOS SwiftUI app and two command-line binaries that detect the musical key of audio, all
built from one Swift package (Swift 6.2+). There is no Xcode project.

Each program has one job. An audio consumer is not a web server.

| Binary / Target | Job | Links |
|---|---|---|
| `MockingBirdCore` | Pure Swift DSP library. Compiles on Linux. Only platform import: guarded Accelerate in `FFTProcessor`. | — |
| `AudioSourceAVFoundation` | macOS mic capture (AVAudioEngine) and file decoding (AVAudioFile). macOS only. | MockingBirdCore |
| `CMiniAudio` | Vendored `Vendor/miniaudio/miniaudio.h` plus the `mb_` C bridge (`miniaudio_bridge.h/.c`). | — |
| `AudioSourceMiniAudio` | Linux/POSIX capture and file decoding via miniaudio. Also builds on macOS. | MockingBirdCore, CMiniAudio |
| `mockingbird` (`MockingBirdCLI`) | DSP CLI. Reads PCM or audio files (stdin/file/device), writes KeyResult JSON to stdout. No HTTP. | MockingBirdCore + platform AudioSource |
| `mockingbird-server` (`MockingBirdServer`) | HTTP/WebSocket gateway. Spawns `mockingbird` subprocesses. No DSP. | Hummingbird only |
| `MockingBirdApp` | SwiftUI macOS app, an SPM executable target; `scripts/bundle-app.sh` wraps it into `build/MockingBird.app`. Links Core in-process. macOS only. | MockingBirdCore, AudioSourceAVFoundation |
| `MockingBirdTestSupport` | Shared test helpers: `ToneSynth`, `SyntheticSource`, `AudioFixture`, `BuiltProducts`. Test-only. | MockingBirdCore |

Apple-only targets are added in `Package.swift` under `#if os(macOS)`, so plain `swift build` /
`swift test` work on Linux. Interfaces between the CLI, server and app (flags, exit codes,
routes, JSON) are specified in README.md; keep them in sync.

### Process Pool (`mockingbird-server`)
- `maxConnections` (default 4, `--max-connections` flag)
- Each connection → one dedicated `mockingbird` subprocess
- Connections beyond max **queue** — never rejected
- No process reuse across connections; each gets a fresh process

Full wiki and architecture: https://www.notion.so/344fe55904c881d69fa8eaa22ae46ebe
Full coding contract: https://www.notion.so/346fe55904c881578e75e69e3c82bea1

---

## Architectural Invariants (Hard Rules)

1. **Never import AVFoundation, AppKit, UIKit, or any Apple framework inside `MockingBirdCore`.** It must compile on Linux. One sanctioned exception: `FFTProcessor` may `import Accelerate` inside `#if canImport(Accelerate)` to use vDSP, and must keep the pure-Swift `RadixTwoFFT` path for everywhere else. No other file in Core imports anything but Foundation.
2. **The audio real-time callback must never allocate on the heap, lock, or call the Swift runtime.** Pre-allocate at init.
3. **Each `AnalysisPipeline` actor exclusively owns its DSP stack.** No shared `FFTProcessor`, `ChromaExtractor`, or `KeyDetector` between pipelines.
4. **`KeyResult`, `ChromaVector`, `AudioConfig`, `ScaleProfile` are value types (`struct`).** Never convert to class.
5. **All new `AudioSource` implementations must conform to the `AudioSource` protocol** and deliver via `AsyncThrowingStream<[Float], Error>`.
6. **No structured concurrency violations.** Use `async/await`, `actor`, `Task`. No `DispatchQueue`, no `Thread`, no `pthread` in new Swift code.

---

## Key Types (MockingBirdCore)

```
PitchClass        — enum, 12 cases, sharps only; Codable as "C" … "B" (decodes legacy ints 0–11)
ScaleCategory     — enum (.major .minor .mode .blues .jazz .pentatonic .symmetric .custom)
KeyResult         — struct: key, scaleName, category, confidence (Pearson r clamped to 0–1), alternates
                    (≤ numAlternates, descending), timestamp = audio seconds at end of window:
                    (windowIndex * hopSize + windowSize) / sampleRate — deterministic, not wall-clock
ChromaVector      — struct: bins ([Float] count==12), sampleRate, windowSize
ChromaAggregation — enum: .perWindow | .cumulative | .rolling(windows:) — how chroma combines across windows
AudioConfig       — struct: sampleRate=44100, windowSize=4096, hopSize=2048, numAlternates=3, zeroPad=false
ScaleProfile      — struct: name, root, category, scaleName, weights ([Float] count==12), Codable, validated on decode
ProfileLibrary    — struct: profiles, static .default (16 scale types x 12 roots = 192 profiles)
AudioSource       — protocol: start(sampleRate:) throws -> AsyncThrowingStream<[Float], Error>, stop()
AudioSourceError  — enum: .permissionDenied, .deviceUnavailable, .formatUnsupported, .deviceDisconnected, .unknown
AnalysisPipeline  — actor: owns FFTProcessor + ChromaExtractor + ChromaAccumulator + KeyDetector, one per job;
                    init(source:config:library:aggregation:), one KeyResult per hop in every mode
ChromaAccumulator — value type: applies ChromaAggregation to un-normalised chroma (loud windows weigh more)
FFTProcessor      — Blackman window, optional zero-padding, vDSP behind canImport(Accelerate) else RadixTwoFFT
RadixTwoFFT       — pure-Swift iterative radix-2 FFT, same magnitude scale as the vDSP path; always compiled
ChromaExtractor   — spectral peaks only (local maxima > 2 % of window max, parabolic interpolation on log
                    magnitude, 65–2000 Hz) → pitch class; extract() L2-normalised, extractEnergy() raw
KeyDetector       — Pearson correlation against every ProfileLibrary profile; confidence = r clamped to [0, 1]

Live input (CLI --continuous, app Listen, server /stream) uses
.rolling(windows: max(1, Int(15 * sampleRate / Double(hopSize)))) ≈ 15 s; whole-input answers use
.cumulative and take the last result. Pearson replaced cosine similarity because cosine scored white
noise 0.95 and always preferred pentatonic profiles; do not switch back.
```

---

## Coding Style

### Generic
- Clarity over cleverness. One type/function, one responsibility.
- No `print()` in production — structured logging abstraction only.
- All public APIs get documentation comments.
- All error types crossing module boundaries must be `Codable`.
- No `!` force unwraps, `try!`, or `fatalError` in production code paths.

### Failure Taxonomy
Two categories. No others.
- **Invariant violations** (caller broke a contract) → `precondition()`. Crash. Fix the code. Never handle at runtime.
  - *e.g. FFTProcessor buffer size != config.windowSize, KeyDetector initialized with empty ProfileLibrary*
- **System constraint failures** (valid request, runtime can't fulfill it) → throw typed error → propagate as `PipelineError` with `ErrorContext` → hard failure of that subsystem. No silent recovery, no retry, no fallback.
  - *e.g. vDSP_DFT_Setup returns nil, audio device init fails, disk full*

### Swift (defers to Swift API Design Guidelines)
- Types: `UpperCamelCase`. Functions/properties: `lowerCamelCase`. Enum cases: `lowerCamelCase`.
- `AudioSource` implementations: `[Platform]Source` pattern — `AVFoundationSource`, `MiniAudioSource`, `FileSource`, `RawPCMSource`.
- Default `struct` over `class`. Default `let` over `var`. Use `guard` for early exits.
- Typed errors over `Error` erasure at module boundaries. Never `try!` in production.

### C / miniaudio bridge (defers to LLVM style)
- All project C functions prefixed `mb_`.
- Every return value must be checked — no silent ignores.
- No global mutable state outside `ma_device` lifecycle.

### Files & Directories
- One primary type per file, named to match: `FFTProcessor.swift`, `AVFoundationSource.swift`.
- Tests mirror source: `FFTProcessorTests.swift` tests `FFTProcessor.swift`.
- No `Utils.swift` / `Helpers.swift` dumping grounds. Extensions go in `Type+Domain.swift` (e.g. `Float+DSP.swift`).
- C files: `snake_case.c` / `snake_case.h`.
- **Data separate from logic.** A model type (`struct`, `enum`) must not be declared in the same file as the logic that consumes it. `FFTProcessor.swift` does not declare `FFTResult`. Models live in their own files.
- **Prefer subdirectories over flat piles.** Unrelated types must not share a directory. If a file exceeds ~500 lines, it likely contains logic that belongs in a sibling directory. Example: `Profiles/` and `KeyDetection/` are separate — `ProfileLibrary` and `KeyDetector` are distinct concerns.
- **Repository layout:**
  ```
  Package.swift                 ← single manifest; Apple-only targets under #if os(macOS)
  Sources/
    MockingBirdCore/
      Audio/          ← AudioSource protocol, AudioSourceError
      Pipeline/       ← AnalysisPipeline actor, ChromaAccumulator, PipelineError
      DSP/
        FFT/          ← FFTProcessor, RadixTwoFFT
        Chroma/       ← ChromaExtractor
      Profiles/       ← ScaleProfile, ScaleCategory, ProfileLibrary
      KeyDetection/   ← KeyDetector
      Models/         ← PitchClass, AudioConfig, ChromaVector, ChromaAggregation, KeyResult
      Sources/        ← FileSource, RawPCMSource
    AudioSourceAVFoundation/    ← AVFoundationSource, AVFoundationFileSource (macOS)
    CMiniAudio/                 ← miniaudio_bridge.c, include/miniaudio_bridge.h
    AudioSourceMiniAudio/       ← MiniAudioSource, MiniAudioFileSource
    MockingBirdCLI/             ← `mockingbird`
    MockingBirdServer/          ← `mockingbird-server`
    MockingBirdApp/
      App/            ← @main entry point (the only place real sources are wired), LaunchArguments
      ViewModels/     ← KeyDetectionViewModel
      Views/          ← one SwiftUI view per file
      Models/         ← DetectionState, KeyDetectionDependencies, KeyPresentation
  Tests/
    MockingBirdTestSupport/     ← shared helpers (ToneSynth, SyntheticSource, AudioFixture, BuiltProducts)
    MockingBird{Core,CLI,Server,MiniAudio,App}Tests/
  Support/MockingBirdApp/Info.plist
  Vendor/miniaudio/             ← miniaudio.h, VERSION, licence
  scripts/
    test.sh           ← swift test + flags Swift Testing needs under Command Line Tools
    bundle-app.sh     ← release build → ad-hoc-signed build/MockingBird.app
    linux.sh          ← build|test|shell in the swift:6.2 Docker image
  ```

### Functional Style — Layer-Aware Rules

The pipeline has three layers with different rules:

| Layer | Allocation | Style |
|---|---|---|
| `AudioSource` callback (I/O) | **Forbidden.** Pre-allocate at init. | Imperative by necessity |
| DSP layer (`FFTProcessor`, `ChromaExtractor`, `KeyDetector`) | **Allowed.** Runs on actor thread. | Purely functional — stateless, same input → same output |
| Coordination / application | Allowed. | Functional preferred |

- DSP components are **stateless pure functions**. No internal mutable state. No side effects.
- `vDSP` operations are functional in behavior (input in, output out) even when using pre-allocated buffers — prefer them in DSP hot paths.
- Prefer `.map`, `.flatMap`, `.filter`, `.reduce` in DSP and application layers. Forbidden only in the `AudioSource` real-time callback.
- Be stateless where possible. Do not declare a mutable `var` with an undefined value to populate later.
- Prefer typed collections — no `[Any]`, use generics.

### Memory Management
- `AnalysisPipeline` holds **strong ownership** of its DSP components. DSP components hold no references back — the ownership graph is acyclic, ARC handles cleanup automatically.
- `AudioSource` implementations hold a **weak reference** to their stream continuation if a back-reference is needed.
- **Philosophy:** start with reference semantics where appropriate, use ARC deliberately, prevent retain cycles through acyclic ownership, trust the runtime. Do not prematurely optimize allocation patterns outside the audio callback.

### Testing
- **Swift Testing only:** `import Testing`, `@Test`, `#expect`, `#require`, `@Suite`. No XCTest.
- **Run tests with `./scripts/test.sh`** (forwards arguments to `swift test`, e.g.
  `./scripts/test.sh --filter MockingBirdCoreTests`) or `make test` / `make test-core|cli|server|miniaudio|app`.
  With only Command Line Tools installed, plain `swift test` cannot find the Testing framework; the
  script adds the framework and rpath flags. With Xcode, or on Linux, it is plain `swift test`.
- **Linux:** `make linux-build` / `make linux-test` (`scripts/linux.sh`, Docker `swift:6.2`).
- **Shared helpers live in `MockingBirdTestSupport`:** `ToneSynth` (deterministic cadences, melodies,
  chords), `SyntheticSource` (an `AudioSource` over a fixed buffer), `AudioFixture` (raw Float32 and
  16-bit WAV bytes, temp files), `BuiltProducts.executable(_:)` (locates built binaries for process
  tests). Suite-specific fakes go in that suite's own directory.
- No test touches real hardware: inject sources (the app's `KeyDetectionDependencies`), use the
  miniaudio null backend, or spawn the built CLI. Anything needing the microphone is a manual check.
- Detection accuracy is checked against synthetic signals: cadences and scale melodies in all 12
  major and minor keys must come out exactly right.

### Commits (Conventional Commits + ticket reference)
```
feat: [MB-3] implement Blackman window in FFTProcessor
fix: [MB-7] clamp confidence scores to [0, 1] in KeyDetector
refactor: [MB-9] extract chroma bin mapping to ChromaExtractor
test: [MB-3] add sine wave reference tests for FFTProcessor
chore: [MB-1] vendor miniaudio 0.11.21
docs: [MB-1] add DSP carve-out to coding contract
```
- Format: `<type>: [MB-N] <subject>`
- Present tense, imperative mood. Subject ≤ 72 chars. Body explains *why*.

---

## Q&A Quick Reference

**Struct or class?** Default struct. Class only for reference semantics, ObservableObject, or ObjC inheritance.

**When to comment?** When the *why* isn't derivable from the code. Never comment the *what*.

**Platform code goes where?** Never in MockingBirdCore. Apple → AudioSourceAVFoundation. Linux → AudioSourceMiniAudio.

**Audio callback threading?** Return immediately. No allocations, no locks, no UI, no Swift runtime. Pre-allocate at init.

**Imperative loops in DSP?** Yes — `.map`/`.filter` allocate. DSP hot path uses index-based loops with pre-allocated buffers. Functional style applies everywhere else.

**CLI vs API errors?** CLI: human-readable stderr + non-zero exit. HTTP API: Codable JSON body + appropriate status code.

**New dependency?** Core: zero deps preferred, must compile on Linux. CLI: SPM packages over system libs. App: Apple frameworks only unless compelling reason.

**Where does the app's logic go?** In `KeyDetectionViewModel` or a model type, tested with injected sources. Views only render. Real `AVFoundationSource` / `AVFoundationFileSource` / `AVCaptureDevice.requestAccess` are referenced only in `App/MockingBirdApp.swift`, and the microphone is opened only when the user presses Listen.

**New scale profile?** Define 12-element normalized weight vector (index 0=C … 11=B). Add all 12 transpositions. Add to ProfileLibrary.default. Add test in ProfileLibraryTests.

---

## Sprint Tracking
Tickets: https://www.notion.so/fef43cffe2a941c1b0de81e835840e08
Sprints:  https://www.notion.so/bbbdf2443ad646d1a28bc6378f5c499f
Sprint 1 · Foundation & Architecture (2026-04-15 → 2026-04-29): done (MB-1).
Completion (2026-11-15): plan in `docs/plans/2026-11-15-finish-mockingbird.md`. Tickets:
MB-2…MB-17 as originally scoped, plus MB-18 Swift Testing and test infrastructure, MB-19 CLI
interface, MB-20 audio file decoding, MB-21 chroma aggregation and detection accuracy, MB-22 SwiftUI
app and bundle, MB-23 build, CI, docs. Out of scope: notarization, iOS, an Xcode project.
