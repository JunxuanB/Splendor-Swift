import Foundation

/// Everything the local tutorial host needs to start a throwaway teaching match.
/// The scripted actions are consumed only while the matching bot owns the turn;
/// normal bot decision-making takes over when the queue is released or exhausted.
public struct TutorialMatchSetup: Sendable {
    public let state: GameState
    public let participants: [Participant]
    public let scriptedOpponentID: UUID?
    public let scriptedOpponentActions: [GameAction]

    public init(
        state: GameState,
        participants: [Participant],
        scriptedOpponentID: UUID? = nil,
        scriptedOpponentActions: [GameAction] = []
    ) {
        self.state = state
        self.participants = participants
        self.scriptedOpponentID = scriptedOpponentID
        self.scriptedOpponentActions = scriptedOpponentActions
    }
}

/// A hand-authored, fully deterministic single-player board used by the standard
/// mode tutorial. Unlike `StandardRuleset.makeGame` (which always shuffles), this
/// produces an identical, scripted layout every time so the guided steps can rely
/// on specific cards, a specific noble, and pre-seeded tokens/bonuses.
///
/// The learner is the only player. Every guided action is affordable from the
/// starting state, and the noble's requirement is engineered to be met exactly by
/// the third guided purchase — see the step script in the tutorial UI layer.
public enum TutorialScenario {
    /// Prestige awarded by pre-owned cards. Guided play adds +1 (first buy), +0
    /// (discount example), +1 (noble trigger), and +3 (noble) → 9, leaving a short
    /// free-play tail to reach `targetPrestige` (10).
    public static let targetPrestige = 10

    public static func standard(playerID: UUID, nickname: String) -> TutorialMatchSetup {
        let participant = Participant(
            id: playerID,
            nickname: nickname,
            kind: .human,
            isHost: true
        )
        var player = PlayerState(participant: participant)
        player.purchasedCards = preOwnedCards
        player.tokens = [.sapphire: 1, .onyx: 1, .diamond: 1, .ruby: 1]

        let configuration = GameConfiguration(
            mode: .standard,
            targetPrestige: targetPrestige,
            turnDurationSeconds: nil,
            turnGracePeriodEnabled: false,
            affordableCardHighlightEnabled: true
        )

        let state = GameState(
            gameID: UUID(),
            configuration: configuration,
            players: [player],
            bank: [.diamond: 5, .sapphire: 5, .emerald: 5, .ruby: 5, .onyx: 5, .gold: 5],
            decks: decks,
            market: market,
            availableNobles: [tutorialNoble],
            currentPlayerIndex: 0,
            startingPlayerIndex: 0,
            roundNumber: 1,
            finalRoundTriggered: false,
            status: .playing,
            result: nil,
            revision: 0
        )
        return TutorialMatchSetup(state: state, participants: [participant])
    }

    // MARK: - Well-known IDs (referenced by the guided step highlights)

    /// The affordable card the learner buys in the "buy a card" step.
    public static let affordableCardID = "tut-a"
    /// Costs five diamonds: three permanent bonuses plus two diamond tokens.
    public static let permanentExampleCardID = "tut-b"
    /// The card the learner buys to complete the noble in the "noble visit" step.
    public static let nobleTriggerCardID = "tut-n"
    /// The expensive card highlighted in the "reserve a card" step.
    public static let reserveTargetID = "tut-r"

    // MARK: - Fixed content

    /// Six pre-owned cards: bonuses diamond×2, sapphire×2, emerald×2; prestige 4.
    private static let preOwnedCards: [DevelopmentCard] = [
        card("tut-pre-1", tier: 1, prestige: 1, bonus: .diamond, cost: [:]),
        card("tut-pre-2", tier: 1, prestige: 1, bonus: .diamond, cost: [:]),
        card("tut-pre-3", tier: 1, prestige: 1, bonus: .sapphire, cost: [:]),
        card("tut-pre-4", tier: 1, prestige: 1, bonus: .sapphire, cost: [:]),
        card("tut-pre-5", tier: 1, prestige: 0, bonus: .emerald, cost: [:]),
        card("tut-pre-6", tier: 1, prestige: 0, bonus: .emerald, cost: [:])
    ]

    /// Requires diamond 4 + sapphire 3. Buying `tut-b` lifts sapphire to 3 but
    /// remains one diamond short; `tut-n` supplies the fourth diamond bonus.
    private static let tutorialNoble = NobleTile(
        id: "tut-noble-1",
        prestige: 3,
        requirement: [.diamond: 4, .sapphire: 3]
    )

    private static let market: [Int: [DevelopmentCard]] = [
        1: [
            // tut-a: pay sapphire1 + onyx1 (after sapphire2 discount). Bonus diamond.
            card("tut-a", tier: 1, prestige: 1, bonus: .diamond, cost: [.sapphire: 3, .onyx: 1]),
            // tut-b: exactly demonstrates cost 5 = diamond bonus3 + diamond tokens2.
            card("tut-b", tier: 1, prestige: 0, bonus: .sapphire, cost: [.diamond: 5]),
            card("tut-f1", tier: 1, prestige: 1, bonus: .onyx, cost: [.emerald: 3]),
            card("tut-f2", tier: 1, prestige: 0, bonus: .ruby, cost: [.onyx: 2])
        ],
        2: [
            // Uses the learner's three rubies plus reserved gold, then completes the noble.
            card("tut-n", tier: 2, prestige: 1, bonus: .diamond, cost: [.ruby: 4]),
            card("tut-t2-2", tier: 2, prestige: 1, bonus: .onyx, cost: [.emerald: 2, .ruby: 3]),
            card("tut-t2-3", tier: 2, prestige: 2, bonus: .emerald, cost: [.sapphire: 3, .onyx: 3]),
            card("tut-t2-4", tier: 2, prestige: 3, bonus: .diamond, cost: [.onyx: 5])
        ],
        3: [
            // tut-r: expensive, high prestige — a natural reserve target.
            card("tut-r", tier: 3, prestige: 4, bonus: .diamond, cost: [.sapphire: 3, .onyx: 3, .ruby: 5]),
            card("tut-t3-2", tier: 3, prestige: 3, bonus: .ruby, cost: [.diamond: 3, .sapphire: 3, .emerald: 5, .onyx: 3]),
            card("tut-t3-3", tier: 3, prestige: 4, bonus: .onyx, cost: [.emerald: 7]),
            card("tut-t3-4", tier: 3, prestige: 5, bonus: .emerald, cost: [.diamond: 7, .sapphire: 3])
        ]
    ]

    /// Small non-empty draw piles so the deck buttons render and blind reserve works.
    private static let decks: [Int: [DevelopmentCard]] = [
        1: [
            card("tut-d1-1", tier: 1, prestige: 0, bonus: .ruby, cost: [.diamond: 1, .sapphire: 1, .emerald: 1]),
            card("tut-d1-2", tier: 1, prestige: 0, bonus: .onyx, cost: [.emerald: 2, .ruby: 1])
        ],
        2: [
            card("tut-d2-1", tier: 2, prestige: 1, bonus: .sapphire, cost: [.diamond: 2, .ruby: 4]),
            card("tut-d2-2", tier: 2, prestige: 2, bonus: .diamond, cost: [.emerald: 5])
        ],
        3: [
            card("tut-d3-1", tier: 3, prestige: 3, bonus: .sapphire, cost: [.emerald: 3, .ruby: 3, .onyx: 5]),
            card("tut-d3-2", tier: 3, prestige: 4, bonus: .ruby, cost: [.diamond: 7])
        ]
    ]

    private static func card(
        _ id: String,
        tier: Int,
        prestige: Int,
        bonus: GemColor,
        cost: [GemColor: Int]
    ) -> DevelopmentCard {
        DevelopmentCard(id: id, tier: tier, prestige: prestige, bonus: bonus, cost: cost)
    }
}
