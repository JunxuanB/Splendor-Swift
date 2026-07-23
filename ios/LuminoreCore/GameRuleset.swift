import Foundation

public protocol GameRuleset: Sendable {
    func makeGame(
        participants: [Participant],
        configuration: GameConfiguration,
        seed: UInt64
    ) throws -> GameState

    func apply(_ action: GameAction, playerID: UUID, to state: inout GameState) throws
    func setConnection(_ isConnected: Bool, playerID: UUID, in state: inout GameState)
    func skipDisconnectedPlayers(in state: inout GameState)
}

public enum GameRuleError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedMode
    case invalidPlayerCount
    case gameFinished
    case notPlayersTurn
    case invalidAction
    case insufficientTokens
    case tokenLimitViolation
    case cardNotFound
    case reserveLimitReached
    case cardNotAffordable
    case invalidPayment
    case invalidNoble

    public var errorDescription: String? {
        switch self {
        case .unsupportedMode: "The selected mode is not available."
        case .invalidPlayerCount: "A game needs between 2 and 7 players."
        case .gameFinished: "The game has already finished."
        case .notPlayersTurn: "It is not this player's turn."
        case .invalidAction: "This action is not legal."
        case .insufficientTokens: "There are not enough tokens."
        case .tokenLimitViolation: "The player must finish with exactly 10 or fewer tokens."
        case .cardNotFound: "The selected card is no longer available."
        case .reserveLimitReached: "No more than three cards may be reserved."
        case .cardNotAffordable: "The selected card cannot be afforded."
        case .invalidPayment: "The selected payment is invalid."
        case .invalidNoble: "The selected noble is invalid."
        }
    }
}

public struct StandardRuleset: GameRuleset {
    public init() {}

    public func makeGame(
        participants: [Participant],
        configuration: GameConfiguration,
        seed: UInt64 = UInt64.random(in: .min ... .max)
    ) throws -> GameState {
        guard configuration.mode == .standard else { throw GameRuleError.unsupportedMode }
        guard (2 ... 7).contains(participants.count) else { throw GameRuleError.invalidPlayerCount }
        guard Set(participants.map(\.id)).count == participants.count else { throw GameRuleError.invalidPlayerCount }

        var random = SeededGenerator(seed: seed)
        var decks: [Int: [DevelopmentCard]] = [:]
        var market: [Int: [DevelopmentCard]] = [:]
        for tier in 1 ... 3 {
            var cards = StandardCatalog.cards.filter { $0.tier == tier }
            cards.shuffle(using: &random)
            market[tier] = (0 ..< min(4, cards.count)).compactMap { _ in cards.popLast() }
            decks[tier] = cards
        }

        var nobles = StandardCatalog.nobles
        nobles.shuffle(using: &random)
        let startingPlayerIndex = Int.random(in: 0 ..< participants.count, using: &random)

        return GameState(
            gameID: UUID(),
            configuration: configuration,
            players: participants.map(PlayerState.init),
            bank: Self.initialBank(playerCount: participants.count),
            decks: decks,
            market: market,
            availableNobles: Array(nobles.prefix(participants.count + 1)),
            currentPlayerIndex: startingPlayerIndex,
            startingPlayerIndex: startingPlayerIndex,
            roundNumber: 1,
            finalRoundTriggered: false,
            status: .playing,
            result: nil,
            revision: 0
        )
    }

    public func apply(_ action: GameAction, playerID: UUID, to state: inout GameState) throws {
        guard state.status == .playing else { throw GameRuleError.gameFinished }
        guard state.currentPlayer.id == playerID else { throw GameRuleError.notPlayersTurn }

        // Every command is atomic: validation failures must never leak partial
        // token/card mutations into the authoritative state.
        var working = state

        switch action {
        case let .take(tokens, returning):
            try applyTake(tokens: tokens, returning: returning, state: &working)
        case let .reserve(source, returning):
            try applyReserve(source: source, returning: returning, state: &working)
        case let .purchase(source, payment, nobleID):
            try applyPurchase(source: source, payment: payment, nobleID: nobleID, state: &working)
        case .pass:
            break
        }

        working.revision += 1
        completeTurn(state: &working)
        state = working
    }

    public func setConnection(_ isConnected: Bool, playerID: UUID, in state: inout GameState) {
        guard let index = state.players.firstIndex(where: { $0.id == playerID }) else { return }
        state.players[index].isConnected = isConnected
        state.revision += 1
        if !isConnected, state.currentPlayer.id == playerID {
            skipDisconnectedPlayers(in: &state)
        }
    }

    public func skipDisconnectedPlayers(in state: inout GameState) {
        guard state.status == .playing, state.players.contains(where: \.isConnected) else { return }
        var visited = 0
        while !state.currentPlayer.isConnected, visited < state.players.count {
            advanceTurn(state: &state)
            state.revision += 1
            if state.finalRoundTriggered, state.currentPlayerIndex == state.startingPlayerIndex {
                finishGame(state: &state)
                return
            }
            visited += 1
        }
    }

    public static func initialBank(playerCount: Int) -> [GemColor: Int] {
        let colored: Int
        let gold: Int
        switch playerCount {
        case 2: (colored, gold) = (4, 5)
        case 3: (colored, gold) = (5, 5)
        case 4: (colored, gold) = (7, 5)
        case 5: (colored, gold) = (8, 6)
        case 6: (colored, gold) = (9, 7)
        default: (colored, gold) = (10, 8)
        }
        var bank = Dictionary(uniqueKeysWithValues: GemColor.purchasableColors.map { ($0, colored) })
        bank[.gold] = gold
        return bank
    }
}

private extension StandardRuleset {
    func applyTake(tokens: [GemColor: Int], returning: [GemColor: Int], state: inout GameState) throws {
        guard tokens.values.allSatisfy({ $0 >= 0 }), returning.values.allSatisfy({ $0 >= 0 }) else {
            throw GameRuleError.invalidAction
        }
        let picks = tokens.filter { $0.value > 0 }
        guard !picks.isEmpty, picks.keys.allSatisfy({ $0 != .gold }) else { throw GameRuleError.invalidAction }
        guard picks.allSatisfy({ state.bank[$0.key, default: 0] >= $0.value }) else {
            throw GameRuleError.insufficientTokens
        }

        if picks.count == 1, let pick = picks.first, pick.value == 2 {
            guard state.bank[pick.key, default: 0] >= 4 else { throw GameRuleError.invalidAction }
        } else {
            guard picks.values.allSatisfy({ $0 == 1 }) else { throw GameRuleError.invalidAction }
            guard (1 ... 3).contains(picks.count) else { throw GameRuleError.invalidAction }
        }

        let index = state.currentPlayerIndex
        for (color, amount) in picks {
            state.bank[color, default: 0] -= amount
            state.players[index].tokens[color, default: 0] += amount
        }
        try applyReturns(returning, playerIndex: index, state: &state)
    }

    func applyReserve(source: CardSource, returning: [GemColor: Int], state: inout GameState) throws {
        guard returning.values.allSatisfy({ $0 >= 0 }) else { throw GameRuleError.invalidAction }
        let index = state.currentPlayerIndex
        guard state.players[index].reservedCards.count < 3 else { throw GameRuleError.reserveLimitReached }

        let card: DevelopmentCard
        switch source {
        case let .market(cardID):
            guard let located = locateMarketCard(cardID, state: state) else { throw GameRuleError.cardNotFound }
            card = state.market[located.tier]!.remove(at: located.index)
            refillMarket(tier: located.tier, state: &state)
        case let .deck(tier):
            guard (1 ... 3).contains(tier), let hidden = state.decks[tier]?.popLast() else {
                throw GameRuleError.cardNotFound
            }
            card = hidden
        case .reserved:
            throw GameRuleError.invalidAction
        }

        state.players[index].reservedCards.append(card)
        if state.bank[.gold, default: 0] > 0 {
            state.bank[.gold, default: 0] -= 1
            state.players[index].tokens[.gold, default: 0] += 1
        }
        try applyReturns(returning, playerIndex: index, state: &state)
    }

    func applyPurchase(
        source: CardSource,
        payment: [GemColor: Int],
        nobleID: String?,
        state: inout GameState
    ) throws {
        let index = state.currentPlayerIndex
        let card: DevelopmentCard
        let marketLocation: (tier: Int, index: Int)?
        let reservedIndex: Int?

        switch source {
        case let .market(cardID):
            guard let located = locateMarketCard(cardID, state: state) else { throw GameRuleError.cardNotFound }
            card = state.market[located.tier]![located.index]
            marketLocation = located
            reservedIndex = nil
        case let .reserved(cardID):
            guard let located = state.players[index].reservedCards.firstIndex(where: { $0.id == cardID }) else {
                throw GameRuleError.cardNotFound
            }
            card = state.players[index].reservedCards[located]
            marketLocation = nil
            reservedIndex = located
        case .deck:
            throw GameRuleError.invalidAction
        }

        try validatePayment(payment, for: card, player: state.players[index])
        for (color, amount) in payment where amount > 0 {
            state.players[index].tokens[color, default: 0] -= amount
            state.bank[color, default: 0] += amount
        }

        if let marketLocation {
            state.market[marketLocation.tier]!.remove(at: marketLocation.index)
            refillMarket(tier: marketLocation.tier, state: &state)
        } else if let reservedIndex {
            state.players[index].reservedCards.remove(at: reservedIndex)
        }
        state.players[index].purchasedCards.append(card)

        let eligible = state.availableNobles.filter { noble in
            noble.requirement.allSatisfy { state.players[index].bonuses[$0.key, default: 0] >= $0.value }
        }
        if eligible.count == 1 {
            guard nobleID == nil || nobleID == eligible[0].id else { throw GameRuleError.invalidNoble }
            takeNoble(eligible[0], playerIndex: index, state: &state)
        } else if eligible.count > 1 {
            guard let nobleID, let noble = eligible.first(where: { $0.id == nobleID }) else {
                throw GameRuleError.invalidNoble
            }
            takeNoble(noble, playerIndex: index, state: &state)
        } else if nobleID != nil {
            throw GameRuleError.invalidNoble
        }
    }

    func validatePayment(_ payment: [GemColor: Int], for card: DevelopmentCard, player: PlayerState) throws {
        guard payment.values.allSatisfy({ $0 >= 0 }) else { throw GameRuleError.invalidPayment }
        let paid = payment.filter { $0.value > 0 }
        guard paid.allSatisfy({ player.tokens[$0.key, default: 0] >= $0.value }) else {
            throw GameRuleError.insufficientTokens
        }
        var goldRequired = 0
        for color in GemColor.purchasableColors {
            let required = max(0, card.cost[color, default: 0] - player.bonuses[color, default: 0])
            let coloredPayment = paid[color, default: 0]
            guard coloredPayment <= required else { throw GameRuleError.invalidPayment }
            goldRequired += required - coloredPayment
        }
        guard paid[.gold, default: 0] == goldRequired else { throw GameRuleError.invalidPayment }
        guard paid.keys.allSatisfy({ GemColor.allCases.contains($0) }) else { throw GameRuleError.invalidPayment }
    }

    func applyReturns(_ returning: [GemColor: Int], playerIndex: Int, state: inout GameState) throws {
        let returns = returning.filter { $0.value > 0 }
        guard returns.allSatisfy({ state.players[playerIndex].tokens[$0.key, default: 0] >= $0.value }) else {
            throw GameRuleError.insufficientTokens
        }
        let excess = max(0, state.players[playerIndex].tokenCount - 10)
        guard returns.values.reduce(0, +) == excess else { throw GameRuleError.tokenLimitViolation }
        for (color, amount) in returns {
            state.players[playerIndex].tokens[color, default: 0] -= amount
            state.bank[color, default: 0] += amount
        }
    }

    func locateMarketCard(_ id: String, state: GameState) -> (tier: Int, index: Int)? {
        for tier in 1 ... 3 {
            if let index = state.market[tier]?.firstIndex(where: { $0.id == id }) {
                return (tier, index)
            }
        }
        return nil
    }

    func refillMarket(tier: Int, state: inout GameState) {
        if let replacement = state.decks[tier]?.popLast() {
            state.market[tier, default: []].append(replacement)
        }
    }

    func takeNoble(_ noble: NobleTile, playerIndex: Int, state: inout GameState) {
        state.availableNobles.removeAll { $0.id == noble.id }
        state.players[playerIndex].nobles.append(noble)
    }

    func completeTurn(state: inout GameState) {
        if state.currentPlayer.prestige >= state.configuration.targetPrestige {
            state.finalRoundTriggered = true
        }
        advanceTurn(state: &state)
        if state.finalRoundTriggered, state.currentPlayerIndex == state.startingPlayerIndex {
            finishGame(state: &state)
        } else {
            skipDisconnectedPlayers(in: &state)
        }
    }

    func advanceTurn(state: inout GameState) {
        state.currentPlayerIndex = (state.currentPlayerIndex + 1) % state.players.count
        if state.currentPlayerIndex == state.startingPlayerIndex {
            state.roundNumber += 1
        }
    }

    func finishGame(state: inout GameState) {
        state.status = .finished
        let sorted = state.players.sorted {
            if $0.prestige != $1.prestige { return $0.prestige > $1.prestige }
            if $0.developmentCardCount != $1.developmentCardCount {
                return $0.developmentCardCount < $1.developmentCardCount
            }
            return $0.nickname.localizedStandardCompare($1.nickname) == .orderedAscending
        }
        let top = sorted.first
        let winnerIDs = sorted.filter {
            $0.prestige == top?.prestige && $0.developmentCardCount == top?.developmentCardCount
        }.map(\.id)
        var previous: PlayerState?
        var rank = 0
        let standings = sorted.enumerated().map { offset, player in
            if previous == nil || previous?.prestige != player.prestige || previous?.developmentCardCount != player.developmentCardCount {
                rank = offset + 1
            }
            previous = player
            return GameResult.Standing(
                playerID: player.id,
                nickname: player.nickname,
                prestige: player.prestige,
                developmentCards: player.developmentCardCount,
                rank: rank,
                isWinner: winnerIDs.contains(player.id)
            )
        }
        state.result = GameResult(standings: standings, winnerIDs: winnerIDs)
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}
