/// A collection of `ScaleProfile` instances used by `KeyDetector`.
///
/// Use `ProfileLibrary.default` to get the built-in set (major/minor, the church modes,
/// blues, jazz minor and bebop, pentatonic, symmetric scales — 16 scale types in all
/// 12 transpositions, 192 profiles).
/// Provide a custom library to restrict or extend detection.
public struct ProfileLibrary: Codable, Sendable {
    public let profiles: [ScaleProfile]

    public init(profiles: [ScaleProfile]) {
        precondition(!profiles.isEmpty, "ProfileLibrary must not be empty")
        self.profiles = profiles
    }

    private enum CodingKeys: String, CodingKey {
        case profiles
    }

    /// Decodes and validates a library; an empty profile list (or any invalid profile)
    /// throws `DecodingError` instead of trapping.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let profiles = try container.decode([ScaleProfile].self, forKey: .profiles)
        guard !profiles.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .profiles, in: container, debugDescription: "ProfileLibrary must not be empty")
        }
        self.init(profiles: profiles)
    }

    // MARK: - Default library

    /// The built-in profile set. Ships all 12 transpositions for each scale type.
    public static let `default`: ProfileLibrary = {
        var all: [ScaleProfile] = []
        for template in templateProfiles {
            for semitones in 0..<12 {
                all.append(template.transposed(by: semitones))
            }
        }
        return ProfileLibrary(profiles: all)
    }()
}

// MARK: - Template profiles (C root, all other roots generated via transposition)

/// One template per scale type, all rooted on C.
/// Weights are the Temperley-normalized vectors; other scale types use
/// established ethnomusicological profiles or empirically derived approximations.
private let templateProfiles: [ScaleProfile] = [
    // MARK: Major (Temperley 1999) / Minor (Temperley-derived)
    ScaleProfile(
        name: "C major",
        root: .c,
        category: .major,
        scaleName: "major",
        weights: temperleyMajor
    ),
    ScaleProfile(
        name: "C minor",
        root: .c,
        category: .minor,
        scaleName: "minor",
        weights: minorWeights
    ),

    // MARK: Church modes (derived from major profile with modal rotation + tonic emphasis)
    ScaleProfile(name: "C dorian",     root: .c, category: .mode,  scaleName: "dorian",     weights: dorianWeights),
    ScaleProfile(name: "C phrygian",   root: .c, category: .mode,  scaleName: "phrygian",   weights: phrygianWeights),
    ScaleProfile(name: "C lydian",     root: .c, category: .mode,  scaleName: "lydian",      weights: lydianWeights),
    ScaleProfile(name: "C mixolydian", root: .c, category: .mode,  scaleName: "mixolydian", weights: mixolydianWeights),
    ScaleProfile(name: "C locrian",    root: .c, category: .mode,  scaleName: "locrian",    weights: locrianWeights),

    // MARK: Blues
    ScaleProfile(name: "C blues",      root: .c, category: .blues, scaleName: "blues",      weights: bluesWeights),

    // MARK: Jazz
    ScaleProfile(name: "C jazz minor", root: .c, category: .jazz,  scaleName: "jazz minor", weights: jazzMinorWeights),
    ScaleProfile(name: "C bebop dominant", root: .c, category: .jazz, scaleName: "bebop dominant", weights: bebopDominantWeights),
    ScaleProfile(name: "C bebop major",    root: .c, category: .jazz, scaleName: "bebop major",    weights: bebopMajorWeights),

    // MARK: Pentatonic
    ScaleProfile(name: "C major pentatonic", root: .c, category: .pentatonic, scaleName: "major pentatonic", weights: majorPentatonicWeights),
    ScaleProfile(name: "C minor pentatonic", root: .c, category: .pentatonic, scaleName: "minor pentatonic", weights: minorPentatonicWeights),

    // MARK: Symmetric
    ScaleProfile(name: "C whole tone",       root: .c, category: .symmetric, scaleName: "whole tone",       weights: wholeToneWeights),
    ScaleProfile(name: "C diminished (HW)",  root: .c, category: .symmetric, scaleName: "diminished (HW)",  weights: diminishedHWWeights),
    ScaleProfile(name: "C diminished (WH)",  root: .c, category: .symmetric, scaleName: "diminished (WH)",  weights: diminishedWHWeights),
]

// MARK: - Weight vectors (C root, indices 0=C … 11=B)
// All vectors are L2-normalized.

/// Temperley (1999) major key profile.
private let temperleyMajor: [Float] = normalize([5, 2, 3.5, 2, 4.5, 4, 2, 4.5, 2, 3.5, 1.5, 4])

/// Minor key profile. Temperley's (1999) has b7 = 1.5 and natural 7 = 4, which leans
/// harmonic minor and sends natural-minor material to the relative major or dorian.
/// Weighting b7 = 3 and 7 = 3 covers natural and harmonic minor alike.
private let minorWeights: [Float] = normalize([5, 2, 3.5, 4.5, 2, 4, 2, 4.5, 3.5, 2, 3, 3])

// Modes are derived by rotating the major scale's interval structure and
// re-weighting the tonic/dominant to emphasize the modal center.
private let dorianWeights:     [Float] = normalize([5, 2, 3, 4.5, 2, 4, 2, 4.5, 2, 3, 4, 2])
private let phrygianWeights:   [Float] = normalize([5, 4, 2, 4.5, 2, 4, 2, 4.5, 2, 3, 4, 2])
private let lydianWeights:     [Float] = normalize([5, 2, 3.5, 2, 4.5, 4, 4, 4.5, 2, 3.5, 1.5, 2])
private let mixolydianWeights: [Float] = normalize([5, 2, 3.5, 2, 4.5, 4, 2, 4.5, 2, 3.5, 4, 2])
private let locrianWeights:    [Float] = normalize([5, 4, 2, 4.5, 2, 4, 4, 2, 3.5, 2, 3.5, 2])

// Blues scale: 1 b3 4 b5 5 b7 — strong weighting on blue notes.
private let bluesWeights: [Float] = normalize([5, 1, 1, 4, 1, 4, 3, 4, 1, 1, 3, 1])

// Jazz melodic minor (ascending): 1 2 b3 4 5 6 7
private let jazzMinorWeights: [Float] = normalize([5, 1, 3, 4, 1, 3.5, 1, 4.5, 1, 3, 1, 4])

// Bebop dominant: 1 2 3 4 5 6 b7 7 — mixolydian with a passing major seventh.
private let bebopDominantWeights: [Float] = normalize([5, 2, 3.5, 2, 4.5, 4, 2, 4.5, 2, 3.5, 4, 3])

// Bebop major: 1 2 3 4 5 #5 6 7 — major with a passing sharp fifth.
private let bebopMajorWeights: [Float] = normalize([5, 2, 3.5, 2, 4.5, 4, 2, 4.5, 3, 3.5, 1.5, 4])

// Major pentatonic: 1 2 3 5 6
private let majorPentatonicWeights: [Float] = normalize([5, 1, 3, 1, 4, 1, 1, 4, 1, 3, 1, 1])

// Minor pentatonic: 1 b3 4 5 b7
private let minorPentatonicWeights: [Float] = normalize([5, 1, 1, 4, 1, 1, 1, 4.5, 1, 1, 3.5, 1])

// Whole tone: 1 2 3 #4 #5 b7
private let wholeToneWeights: [Float] = normalize([5, 1, 4, 1, 4, 1, 4, 1, 4, 1, 4, 1])

// Diminished (half-whole): 1 b2 b3 3 #4 5 6 b7
private let diminishedHWWeights: [Float] = normalize([5, 4, 1, 4, 1, 4, 1, 4, 1, 4, 1, 4])

// Diminished (whole-half): 1 2 b3 4 b5 b6 6 7
private let diminishedWHWeights: [Float] = normalize([5, 1, 4, 1, 4, 1, 4, 1, 4, 1, 4, 1])

// MARK: - Helpers

private func normalize(_ weights: [Float]) -> [Float] {
    let sumOfSquares = weights.reduce(0) { $0 + $1 * $1 }
    let norm = sumOfSquares.squareRoot()
    guard norm > 0 else { return weights }
    return weights.map { $0 / norm }
}
