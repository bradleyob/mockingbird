# MockingBird — Claude Code Contract

## Project Overview
macOS-native app + two CLI binaries that detect the musical key of an audio snippet.

Each program has one job. An audio consumer is not a web server.

| Binary / Target | Job | Links |
|---|---|---|
| `MockingBirdCore` | Pure Swift DSP library. No platform imports. Compiles on Linux. | — |
| `AudioSourceAVFoundation` | macOS/iOS mic capture (AVAudioEngine) | MockingBirdCore |
| `AudioSourceMiniAudio` | Linux/POSIX mic capture (miniaudio, vendored) | MockingBirdCore |
| `mockingbird` | DSP CLI. Reads PCM (stdin/file/device), writes KeyResult JSON to stdout. No HTTP. | MockingBirdCore + platform AudioSource |
| `mockingbird-server` | HTTP/WebSocket gateway. Spawns `mockingbird` subprocesses. No DSP. | Hummingbird only |
| `MockingBird.xcodeproj` | SwiftUI macOS app. Links MockingBirdCore directly, in-process. | MockingBirdCore |

### Process Pool (`mockingbird-server`)
- `maxConnections` (default 4, `--max-connections` flag)
- Each connection → one dedicated `mockingbird` subprocess
- Connections beyond max **queue** — never rejected
- No process reuse across connections; each gets a fresh process

Full wiki and architecture: https://www.notion.so/344fe55904c881d69fa8eaa22ae46ebe
Full coding contract: https://www.notion.so/346fe55904c881578e75e69e3c82bea1

---

## Architectural Invariants (Hard Rules)

1. **Never import AVFoundation, AppKit, UIKit, or any Apple framework inside `MockingBirdCore`.** It must compile on Linux.
2. **The audio real-time callback must never allocate on the heap, lock, or call the Swift runtime.** Pre-allocate at init.
3. **Each `AnalysisPipeline` actor exclusively owns its DSP stack.** No shared `FFTProcessor`, `ChromaExtractor`, or `KeyDetector` between pipelines.
4. **`KeyResult`, `ChromaVector`, `AudioConfig`, `ScaleProfile` are value types (`struct`).** Never convert to class.
5. **All new `AudioSource` implementations must conform to the `AudioSource` protocol** and deliver via `AsyncThrowingStream<[Float], Error>`.
6. **No structured concurrency violations.** Use `async/await`, `actor`, `Task`. No `DispatchQueue`, no `Thread`, no `pthread` in new Swift code.

---

## Key Types (MockingBirdCore)

```
PitchClass       — enum, 12 cases, sharps only (C, C#, D, ... B)
ScaleCategory    — enum (.major .minor .mode .blues .jazz .pentatonic .symmetric .custom)
KeyResult        — struct: key, scaleName, category, confidence (0–1), alternates (max 3), timestamp
ChromaVector     — struct: bins ([Float] count==12), sampleRate, windowSize
AudioConfig      — struct: sampleRate=44100, windowSize=4096, hopSize=2048, numAlternates=3, zeroPad=false
ScaleProfile     — struct: name, root, category, weights ([Float] count==12), Codable
ProfileLibrary   — struct: profiles, static .default (ships Temperley major/minor + modes + blues + jazz + pentatonic + symmetric)
AudioSource      — protocol: start(sampleRate:) throws -> AsyncThrowingStream<[Float], Error>, stop()
AudioSourceError — enum: .permissionDenied, .deviceUnavailable, .formatUnsupported, .deviceDisconnected, .unknown
AnalysisPipeline — actor: owns FFTProcessor + ChromaExtractor + KeyDetector, one per analysis job
FFTProcessor     — Blackman window, vDSP_fft_zrip, optional zero-padding, returns [Float] magnitudes
ChromaExtractor  — maps FFT magnitudes to 12-bin L2-normalized ChromaVector (65–2000 Hz range)
KeyDetector      — Pearson correlation against ProfileLibrary, normalizes scores, returns KeyResult
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
- **`MockingBirdCore` directory layout:**
  ```
  Sources/MockingBirdCore/
    Audio/          ← AudioSource protocol, AudioSourceError
    Pipeline/       ← AnalysisPipeline actor
    DSP/
      FFT/          ← FFTProcessor
      Chroma/       ← ChromaExtractor
    Profiles/       ← ScaleProfile, ScaleCategory, ProfileLibrary
    KeyDetection/   ← KeyDetector
    Models/         ← PitchClass, AudioConfig, ChromaVector, KeyResult (shared primitives)
    Sources/        ← FileSource, RawPCMSource
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

**New scale profile?** Define 12-element normalized weight vector (index 0=C … 11=B). Add all 12 transpositions. Add to ProfileLibrary.default. Add test in ProfileLibraryTests.

---

## Sprint Tracking
Tickets: https://www.notion.so/fef43cffe2a941c1b0de81e835840e08
Sprints:  https://www.notion.so/bbbdf2443ad646d1a28bc6378f5c499f
Current:  Sprint 1 · Foundation & Architecture (2026-04-15 → 2026-04-29)
