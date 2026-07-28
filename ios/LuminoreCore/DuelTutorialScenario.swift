import Foundation

public extension TutorialScenario {
    /// A down-right diagonal used to teach that lines are not limited to rows.
    static let duelFirstLine = [1, 7, 13]
    static let duelPrivilegeTargetIndex = 3
    static let duelGoldIndex = 4
    static let duelOpponentLine = [15, 16, 17]
    static let duelOpponentPrivilegeTargetIndex = 8
    static let duelPearlLine = [10, 11, 12]

    static let duelDoubleBonusCardID = "tut-duel-double"
    static let duelReserveCardID = "tut-duel-reserve"
    static let duelAbilityCardID = "tut-duel-ability"
    static let duelCrownCardID = "tut-duel-crown"
    static let duelFinalCardID = "tut-duel-final"
    static let duelRoyalID = "tut-duel-royal"

    /// A deterministic two-seat Duel board. The learner always starts, while the
    /// bot performs a short validated script between milestones. The learner ends
    /// guided play at 18 prestige, with a free final card worth two points still
    /// visible for the short free-play finish.
    static func duel(
        playerID: UUID,
        nickname: String,
        opponentNickname: String = "Tutor"
    ) -> TutorialMatchSetup {
        let primaryOpponentID = UUID(uuidString: "00000000-0000-0000-0000-00000000D0E1")!
        let fallbackOpponentID = UUID(uuidString: "00000000-0000-0000-0000-00000000D0E2")!
        let opponentID = playerID == primaryOpponentID ? fallbackOpponentID : primaryOpponentID
        let learner = Participant(id: playerID, nickname: nickname, isHost: true)
        let opponent = Participant(
            id: opponentID,
            nickname: opponentNickname,
            kind: .bot,
            difficulty: .normal
        )

        var learnerState = DuelPlayerState(id: playerID)
        learnerState.tokens = [.sapphire: 1, .ruby: 1]
        learnerState.purchasedCards = duelPreOwnedCards.map {
            DuelOwnedCard(card: $0, assignedWildColor: nil)
        }

        let duel = DuelGameData(
            players: [learnerState, DuelPlayerState(id: opponentID)],
            board: duelBoard,
            bag: [.diamond, .sapphire, .emerald, .ruby, .onyx, .pearl, .gold],
            decks: duelDecks,
            market: duelMarket,
            availableRoyals: [DuelRoyalCard(id: duelRoyalID, prestige: 3)],
            privilegesInPool: DuelRules.privilegeCount,
            randomState: 0xD0E1_F00D
        )
        let configuration = GameConfiguration(
            mode: .duel,
            turnDurationSeconds: nil,
            turnGracePeriodEnabled: false,
            affordableCardHighlightEnabled: true
        )
        let state = GameState(
            gameID: UUID(),
            configuration: configuration,
            players: [PlayerState(participant: learner), PlayerState(participant: opponent)],
            bank: [:],
            decks: [:],
            market: [:],
            availableNobles: [],
            currentPlayerIndex: 0,
            startingPlayerIndex: 0,
            roundNumber: 1,
            finalRoundTriggered: false,
            status: .playing,
            result: nil,
            revision: 0,
            duel: duel
        )

        let opponentActions: [GameAction] = [
            .duel(.take(boardIndices: duelOpponentLine, returning: [:])),
            .duel(.spendPrivilege(boardIndex: duelOpponentPrivilegeTargetIndex)),
            .pass,
            .pass,
            .pass,
            .pass,
            .pass,
            .pass,
        ]
        return TutorialMatchSetup(
            state: state,
            participants: [learner, opponent],
            scriptedOpponentID: opponentID,
            scriptedOpponentActions: opponentActions
        )
    }
}

private extension TutorialScenario {
    static let duelPreOwnedCards: [DuelJewelCard] = [
        duelCard("tut-duel-pre-d", prestige: 3, crowns: 1, bonus: .diamond),
        duelCard("tut-duel-pre-s", prestige: 3, crowns: 1, bonus: .sapphire),
        duelCard("tut-duel-pre-e", prestige: 2, bonus: .emerald),
        duelCard("tut-duel-pre-r", prestige: 2, bonus: .ruby),
        duelCard("tut-duel-pre-o", prestige: 2, bonus: .onyx),
    ]

    static let duelBoard: [DuelTokenColor?] = [
        .diamond, .sapphire, .emerald, .onyx, .gold,
        .ruby, .ruby, .ruby, .sapphire, .diamond,
        .pearl, .pearl, .onyx, .emerald, .gold,
        .ruby, .ruby, .ruby, .ruby, .onyx,
        .gold, .diamond, .sapphire, .emerald, .ruby,
    ]

    static let duelMarket: [Int: [DuelJewelCard]] = [
        1: [
            duelCard(
                duelDoubleBonusCardID,
                prestige: 0,
                bonus: .diamond,
                bonusAmount: 2,
                cost: [.sapphire: 3, .onyx: 2, .pearl: 1]
            ),
            duelCard(
                duelCrownCardID,
                prestige: 1,
                crowns: 1,
                bonus: .sapphire,
                cost: [.diamond: 3]
            ),
            duelCard(
                duelFinalCardID,
                prestige: 2,
                bonus: .emerald,
                cost: [.diamond: 3]
            ),
            duelCard("tut-duel-f1", bonus: .ruby, cost: [.emerald: 4]),
            duelCard("tut-duel-f2", prestige: 1, bonus: .onyx, cost: [.sapphire: 4]),
        ],
        2: [
            duelCard(
                duelAbilityCardID,
                tier: 2,
                prestige: 1,
                isWild: true,
                cost: [.emerald: 2],
                ability: .stealToken
            ),
            duelCard(
                duelReserveCardID,
                tier: 2,
                prestige: 1,
                bonus: .onyx,
                cost: [.ruby: 4]
            ),
            duelCard("tut-duel-f3", tier: 2, prestige: 2, bonus: .ruby, cost: [.pearl: 2, .onyx: 3]),
            duelCard("tut-duel-f4", tier: 2, prestige: 2, bonus: .sapphire, cost: [.emerald: 5]),
        ],
        3: [
            duelCard("tut-duel-f5", tier: 3, prestige: 4, bonus: .diamond, cost: [.ruby: 6]),
            duelCard("tut-duel-f6", tier: 3, prestige: 4, bonus: .emerald, cost: [.onyx: 6]),
            duelCard("tut-duel-f7", tier: 3, prestige: 5, bonus: .sapphire, cost: [.diamond: 7]),
        ],
    ]

    static let duelDecks: [Int: [DuelJewelCard]] = [
        1: [duelCard("tut-duel-d1", bonus: .ruby, cost: [.diamond: 2])],
        2: [duelCard("tut-duel-d2", tier: 2, prestige: 1, bonus: .emerald, cost: [.sapphire: 3])],
        3: [duelCard("tut-duel-d3", tier: 3, prestige: 3, bonus: .onyx, cost: [.emerald: 5])],
    ]

    static func duelCard(
        _ id: String,
        tier: Int = 1,
        prestige: Int = 0,
        crowns: Int = 0,
        bonus: DuelGemColor? = nil,
        bonusAmount: Int = 1,
        isWild: Bool = false,
        cost: [DuelTokenColor: Int] = [:],
        ability: DuelCardAbility? = nil
    ) -> DuelJewelCard {
        DuelJewelCard(
            id: id,
            tier: tier,
            prestige: prestige,
            crowns: crowns,
            bonusColor: bonus,
            bonusAmount: bonus == nil && !isWild ? 0 : bonusAmount,
            isWildBonus: isWild,
            cost: cost,
            ability: ability
        )
    }
}
