import Foundation

/// Host-side AI player. Bots always run on the authoritative host, so they operate
/// on the full `GameState` (not the sanitized client snapshot) and pick a single
/// `GameAction` per invocation. For Duel, optional sub-actions (spend privilege /
/// replenish) leave the turn with the same player, so the driver simply calls
/// `chooseAction` again until the turn advances.
///
/// Every controller guarantees the returned action is legal: candidates are
/// validated by simulating them through the real ruleset, and `.pass` (always
/// legal) is the last-resort fallback. This keeps the AI correct even for Duel's
/// intricate ability/royal/choice rules without re-deriving legality by hand.
public protocol BotController: Sendable {
    func chooseAction(state: GameState, playerID: UUID, difficulty: BotDifficulty) -> GameAction
}

public enum BotFactory {
    public static func make(for mode: GameMode) -> BotController {
        switch mode {
        case .standard, .silkRoad: return StandardBot()
        case .duel: return DuelBot()
        }
    }
}

/// Difficulty knobs shared by both rulesets. `noise` is absolute score jitter
/// (evaluation units where one prestige point ≈ 100), `blunderChance` occasionally
/// forces a random legal move, and `opponentReply` enables one-ply opponent
/// look-ahead ("预判") on the top candidates.
struct BotProfile {
    let noise: Double
    let blunderChance: Double
    let opponentReply: Bool

    static func profile(for difficulty: BotDifficulty) -> BotProfile {
        switch difficulty {
        case .easy: BotProfile(noise: 85, blunderChance: 0.22, opponentReply: false)
        case .normal: BotProfile(noise: 22, blunderChance: 0.02, opponentReply: false)
        case .hard: BotProfile(noise: 0, blunderChance: 0, opponentReply: true)
        }
    }
}

/// Deterministic SplitMix64 — seeded from the position so a bot's jitter is stable
/// for a given state (useful for tests) while still varying turn to turn. Avoids
/// depending on process-seeded `Hasher` or wall-clock randomness.
struct BotRNG {
    private var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    mutating func nextUnit() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    mutating func nextInt(_ upperBound: Int) -> Int {
        upperBound <= 0 ? 0 : Int(next() % UInt64(upperBound))
    }
}

enum BotSelection {
    /// A candidate action paired with the state that results from applying it.
    struct Candidate {
        let action: GameAction
        let result: GameState
        let baseScore: Double
    }

    /// Picks among validated candidates applying the difficulty profile's noise
    /// and blunder behaviour. Returns `.pass` when there is nothing to do.
    static func choose(
        _ candidates: [Candidate],
        profile: BotProfile,
        rng: inout BotRNG
    ) -> GameAction {
        guard !candidates.isEmpty else { return .pass }
        if profile.blunderChance > 0, rng.nextUnit() < profile.blunderChance {
            return candidates[rng.nextInt(candidates.count)].action
        }
        var best = candidates[0]
        var bestScore = -Double.greatestFiniteMagnitude
        for candidate in candidates {
            var score = candidate.baseScore
            if profile.noise > 0 {
                score += (rng.nextUnit() * 2 - 1) * profile.noise
            }
            if score > bestScore {
                bestScore = score
                best = candidate
            }
        }
        return best.action
    }
}

extension GameState {
    var opponentsOfCurrent: [PlayerState] {
        players.enumerated().compactMap { $0.offset == currentPlayerIndex ? nil : $0.element }
    }
}
