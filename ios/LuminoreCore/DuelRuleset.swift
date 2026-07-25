import Foundation

public struct RulesEngine: GameRuleset {
    public init() {}

    public func makeGame(
        participants: [Participant],
        configuration: GameConfiguration,
        seed: UInt64
    ) throws -> GameState {
        switch configuration.mode {
        case .standard: try StandardRuleset().makeGame(participants: participants, configuration: configuration, seed: seed)
        case .duel: try DuelRuleset().makeGame(participants: participants, configuration: configuration, seed: seed)
        case .silkRoad: throw GameRuleError.unsupportedMode
        }
    }

    public func apply(_ action: GameAction, playerID: UUID, to state: inout GameState) throws {
        switch state.configuration.mode {
        case .standard: try StandardRuleset().apply(action, playerID: playerID, to: &state)
        case .duel: try DuelRuleset().apply(action, playerID: playerID, to: &state)
        case .silkRoad: throw GameRuleError.unsupportedMode
        }
    }

    public func setConnection(
        _ isConnected: Bool,
        playerID: UUID,
        skipTurns: Bool = true,
        in state: inout GameState
    ) {
        switch state.configuration.mode {
        case .standard:
            StandardRuleset().setConnection(isConnected, playerID: playerID, skipTurns: skipTurns, in: &state)
        case .duel:
            DuelRuleset().setConnection(isConnected, playerID: playerID, skipTurns: skipTurns, in: &state)
        case .silkRoad:
            break
        }
    }

    public func skipDisconnectedPlayers(in state: inout GameState) {
        switch state.configuration.mode {
        case .standard: StandardRuleset().skipDisconnectedPlayers(in: &state)
        case .duel: DuelRuleset().skipDisconnectedPlayers(in: &state)
        case .silkRoad: break
        }
    }
}

public struct DuelRuleset: GameRuleset {
    public init() {}

    public func makeGame(
        participants: [Participant],
        configuration: GameConfiguration,
        seed: UInt64 = UInt64.random(in: .min ... .max)
    ) throws -> GameState {
        guard configuration.mode == .duel else { throw GameRuleError.unsupportedMode }
        guard participants.count == 2, Set(participants.map(\.id)).count == 2 else {
            throw GameRuleError.invalidPlayerCount
        }

        var random = DuelRandomGenerator(seed: seed)
        var decks: [Int: [DuelJewelCard]] = [:]
        var market: [Int: [DuelJewelCard]] = [:]
        for tier in 1 ... 3 {
            var cards = DuelCatalog.cards.filter { $0.tier == tier }
            cards.shuffle(using: &random)
            let visibleCount = 6 - tier
            market[tier] = (0 ..< visibleCount).compactMap { _ in cards.popLast() }
            decks[tier] = cards
        }

        var tokens = DuelTokenColor.allCases.flatMap { color in
            Array(repeating: color, count: DuelRules.tokenSupply[color, default: 0])
        }
        tokens.shuffle(using: &random)
        var board = Array<DuelTokenColor?>(repeating: nil, count: DuelRules.boardSize * DuelRules.boardSize)
        for (offset, boardIndex) in DuelRules.spiralOrder.enumerated() {
            board[boardIndex] = tokens[offset]
        }

        let startingPlayerIndex = Int.random(in: 0 ..< 2, using: &random)
        var duelPlayers = participants.map { DuelPlayerState(id: $0.id) }
        duelPlayers[(startingPlayerIndex + 1) % 2].privileges = 1
        let duel = DuelGameData(
            players: duelPlayers,
            board: board,
            bag: [],
            decks: decks,
            market: market,
            availableRoyals: DuelCatalog.royals,
            privilegesInPool: 2,
            randomState: random.state
        )

        return GameState(
            gameID: UUID(),
            configuration: configuration,
            players: participants.map(PlayerState.init),
            bank: [:],
            decks: [:],
            market: [:],
            availableNobles: [],
            currentPlayerIndex: startingPlayerIndex,
            startingPlayerIndex: startingPlayerIndex,
            roundNumber: 1,
            finalRoundTriggered: false,
            status: .playing,
            result: nil,
            revision: 0,
            duel: duel
        )
    }

    public func apply(_ action: GameAction, playerID: UUID, to state: inout GameState) throws {
        guard state.configuration.mode == .duel, state.status == .playing, state.duel != nil else {
            throw state.status == .finished ? GameRuleError.gameFinished : GameRuleError.invalidAction
        }
        guard state.currentPlayer.id == playerID else { throw GameRuleError.notPlayersTurn }

        var working = state
        switch action {
        case let .duel(action):
            try applyDuel(action, state: &working)
        case .pass:
            completeTurn(extraTurn: false, state: &working)
        default:
            throw GameRuleError.invalidAction
        }
        working.revision += 1
        state = working
    }

    public func setConnection(
        _ isConnected: Bool,
        playerID: UUID,
        skipTurns: Bool = true,
        in state: inout GameState
    ) {
        guard let index = state.players.firstIndex(where: { $0.id == playerID }) else { return }
        state.players[index].isConnected = isConnected
        state.revision += 1
        if skipTurns, !isConnected, state.currentPlayer.id == playerID {
            skipDisconnectedPlayers(in: &state)
        }
    }

    public func skipDisconnectedPlayers(in state: inout GameState) {
        guard state.status == .playing, state.players.contains(where: \.isConnected) else { return }
        var visited = 0
        while !state.currentPlayer.isConnected, visited < state.players.count {
            advanceTurn(state: &state)
            state.duel?.turnStage = .privilegesAvailable
            state.revision += 1
            visited += 1
        }
    }
}

private extension DuelRuleset {
    func applyDuel(_ action: DuelAction, state: inout GameState) throws {
        switch action {
        case let .spendPrivilege(boardIndex):
            try spendPrivilege(boardIndex: boardIndex, state: &state)
        case .replenish:
            try replenish(state: &state)
        case let .take(boardIndices, returning):
            try take(boardIndices: boardIndices, returning: returning, state: &state)
            completeTurn(extraTurn: false, state: &state)
        case let .reserve(goldBoardIndex, source, returning):
            try reserve(goldBoardIndex: goldBoardIndex, source: source, returning: returning, state: &state)
            completeTurn(extraTurn: false, state: &state)
        case let .purchase(source, payment, choices, returning):
            let extraTurn = try purchase(
                source: source,
                payment: payment,
                choices: choices,
                returning: returning,
                state: &state
            )
            completeTurn(extraTurn: extraTurn, state: &state)
        }
    }

    func spendPrivilege(boardIndex: Int, state: inout GameState) throws {
        guard var duel = state.duel, duel.turnStage == .privilegesAvailable,
              duel.board.indices.contains(boardIndex),
              let color = duel.board[boardIndex], color != .gold
        else { throw GameRuleError.invalidAction }
        let playerIndex = state.currentPlayerIndex
        guard duel.players[playerIndex].privileges > 0 else { throw GameRuleError.invalidAction }
        duel.board[boardIndex] = nil
        duel.players[playerIndex].tokens[color, default: 0] += 1
        duel.players[playerIndex].privileges -= 1
        duel.privilegesInPool += 1
        state.duel = duel
    }

    func replenish(state: inout GameState) throws {
        guard var duel = state.duel, duel.turnStage == .privilegesAvailable, !duel.bag.isEmpty else {
            throw GameRuleError.invalidAction
        }
        var random = DuelRandomGenerator(rawState: duel.randomState)
        duel.bag.shuffle(using: &random)
        for index in DuelRules.spiralOrder where duel.board[index] == nil && !duel.bag.isEmpty {
            duel.board[index] = duel.bag.removeLast()
        }
        duel.randomState = random.state
        grantPrivilege(to: opponentIndex(of: state.currentPlayerIndex), duel: &duel)
        duel.turnStage = .mandatoryOnly
        state.duel = duel
    }

    func take(
        boardIndices: [Int],
        returning: [DuelTokenColor: Int],
        state: inout GameState
    ) throws {
        guard var duel = state.duel, (1 ... 3).contains(boardIndices.count),
              Set(boardIndices).count == boardIndices.count,
              isStraightUninterruptedLine(boardIndices)
        else { throw GameRuleError.invalidAction }
        let colors = try boardIndices.map { index -> DuelTokenColor in
            guard duel.board.indices.contains(index), let color = duel.board[index], color != .gold else {
                throw GameRuleError.invalidAction
            }
            return color
        }
        let playerIndex = state.currentPlayerIndex
        for (index, color) in zip(boardIndices, colors) {
            duel.board[index] = nil
            duel.players[playerIndex].tokens[color, default: 0] += 1
        }
        if (colors.count == 3 && Set(colors).count == 1) || colors.count(where: { $0 == .pearl }) >= 2 {
            grantPrivilege(to: opponentIndex(of: playerIndex), duel: &duel)
        }
        try applyReturns(returning, playerIndex: playerIndex, duel: &duel)
        state.duel = duel
    }

    func reserve(
        goldBoardIndex: Int,
        source: DuelCardSource,
        returning: [DuelTokenColor: Int],
        state: inout GameState
    ) throws {
        guard var duel = state.duel, duel.board.indices.contains(goldBoardIndex),
              duel.board[goldBoardIndex] == .gold
        else { throw GameRuleError.invalidAction }
        let playerIndex = state.currentPlayerIndex
        guard duel.players[playerIndex].reservedCards.count < DuelRules.reserveLimit else {
            throw GameRuleError.reserveLimitReached
        }
        let card = try removeCard(source: source, allowsReserved: false, playerIndex: playerIndex, duel: &duel)
        duel.board[goldBoardIndex] = nil
        duel.players[playerIndex].tokens[.gold, default: 0] += 1
        duel.players[playerIndex].reservedCards.append(card)
        try applyReturns(returning, playerIndex: playerIndex, duel: &duel)
        state.duel = duel
    }

    func purchase(
        source: DuelCardSource,
        payment: [DuelTokenColor: Int],
        choices: DuelPurchaseChoices,
        returning: [DuelTokenColor: Int],
        state: inout GameState
    ) throws -> Bool {
        guard var duel = state.duel else { throw GameRuleError.invalidAction }
        let playerIndex = state.currentPlayerIndex
        if case .deck = source { throw GameRuleError.invalidAction }
        let card = try locateCard(source: source, playerIndex: playerIndex, duel: duel)
        let playerBefore = duel.players[playerIndex]
        try validatePayment(payment, card: card, player: playerBefore)

        let assignedColor: DuelGemColor?
        if card.isWildBonus {
            guard let choice = choices.wildBonusColor, playerBefore.bonuses[choice, default: 0] > 0 else {
                throw GameRuleError.invalidAction
            }
            assignedColor = choice
        } else {
            guard choices.wildBonusColor == nil else { throw GameRuleError.invalidAction }
            assignedColor = nil
        }

        for (color, count) in payment where count > 0 {
            duel.players[playerIndex].tokens[color, default: 0] -= count
            duel.bag.append(contentsOf: Array(repeating: color, count: count))
        }
        _ = try removeCard(source: source, allowsReserved: true, playerIndex: playerIndex, duel: &duel)
        duel.players[playerIndex].purchasedCards.append(
            DuelOwnedCard(card: card, assignedWildColor: assignedColor)
        )

        var extraTurn = try resolve(
            ability: card.ability,
            effectiveColor: card.isWildBonus ? assignedColor : card.bonusColor,
            boardIndex: choices.abilityBoardIndex,
            stolenToken: choices.stolenToken,
            playerIndex: playerIndex,
            duel: &duel
        )

        let oldCrowns = playerBefore.crowns
        let newCrowns = duel.players[playerIndex].crowns
        let earnedRoyal = (oldCrowns < 3 && newCrowns >= 3) || (oldCrowns < 6 && newCrowns >= 6)
        if earnedRoyal {
            guard let royalID = choices.royalID,
                  let royalIndex = duel.availableRoyals.firstIndex(where: { $0.id == royalID })
            else { throw GameRuleError.invalidNoble }
            let royal = duel.availableRoyals.remove(at: royalIndex)
            duel.players[playerIndex].royalCards.append(royal)
            extraTurn = try resolve(
                ability: royal.ability,
                effectiveColor: nil,
                boardIndex: nil,
                stolenToken: choices.royalStolenToken,
                playerIndex: playerIndex,
                duel: &duel
            ) || extraTurn
        } else if choices.royalID != nil || choices.royalStolenToken != nil {
            throw GameRuleError.invalidNoble
        }

        try applyReturns(returning, playerIndex: playerIndex, duel: &duel)
        state.duel = duel
        return extraTurn
    }

    func resolve(
        ability: DuelCardAbility?,
        effectiveColor: DuelGemColor?,
        boardIndex: Int?,
        stolenToken: DuelTokenColor?,
        playerIndex: Int,
        duel: inout DuelGameData
    ) throws -> Bool {
        switch ability {
        case nil:
            guard boardIndex == nil, stolenToken == nil else { throw GameRuleError.invalidAction }
            return false
        case .extraTurn:
            guard boardIndex == nil, stolenToken == nil else { throw GameRuleError.invalidAction }
            return true
        case .takePrivilege:
            guard boardIndex == nil, stolenToken == nil else { throw GameRuleError.invalidAction }
            grantPrivilege(to: playerIndex, duel: &duel)
            return false
        case .takeMatchingToken:
            guard let effectiveColor else { throw GameRuleError.invalidAction }
            let token = DuelTokenColor(effectiveColor)
            let matchingIndices = duel.board.indices.filter { duel.board[$0] == token }
            if matchingIndices.isEmpty {
                guard boardIndex == nil else { throw GameRuleError.invalidAction }
            } else {
                guard let boardIndex, matchingIndices.contains(boardIndex) else { throw GameRuleError.invalidAction }
                duel.board[boardIndex] = nil
                duel.players[playerIndex].tokens[token, default: 0] += 1
            }
            guard stolenToken == nil else { throw GameRuleError.invalidAction }
            return false
        case .stealToken:
            guard boardIndex == nil else { throw GameRuleError.invalidAction }
            let opponent = opponentIndex(of: playerIndex)
            let stealable = DuelTokenColor.boardTakeable.filter { duel.players[opponent].tokens[$0, default: 0] > 0 }
            if stealable.isEmpty {
                guard stolenToken == nil else { throw GameRuleError.invalidAction }
            } else {
                guard let stolenToken, stealable.contains(stolenToken) else { throw GameRuleError.invalidAction }
                duel.players[opponent].tokens[stolenToken, default: 0] -= 1
                duel.players[playerIndex].tokens[stolenToken, default: 0] += 1
            }
            return false
        }
    }

    func validatePayment(
        _ payment: [DuelTokenColor: Int],
        card: DuelJewelCard,
        player: DuelPlayerState
    ) throws {
        guard payment.values.allSatisfy({ $0 >= 0 }),
              payment.allSatisfy({ player.tokens[$0.key, default: 0] >= $0.value })
        else { throw GameRuleError.invalidPayment }
        var goldRequired = 0
        for token in DuelTokenColor.boardTakeable {
            let discount = token.gemColor.map { player.bonuses[$0, default: 0] } ?? 0
            let required = max(0, card.cost[token, default: 0] - discount)
            let paid = payment[token, default: 0]
            guard paid <= required else { throw GameRuleError.invalidPayment }
            goldRequired += required - paid
        }
        guard payment[.gold, default: 0] == goldRequired else { throw GameRuleError.invalidPayment }
    }

    func locateCard(
        source: DuelCardSource,
        playerIndex: Int,
        duel: DuelGameData
    ) throws -> DuelJewelCard {
        switch source {
        case let .market(cardID):
            for tier in 1 ... 3 {
                if let card = duel.market[tier]?.first(where: { $0.id == cardID }) { return card }
            }
        case let .deck(tier):
            if (1 ... 3).contains(tier), let card = duel.decks[tier]?.last { return card }
        case let .reserved(cardID):
            if let card = duel.players[playerIndex].reservedCards.first(where: { $0.id == cardID }) { return card }
        }
        throw GameRuleError.cardNotFound
    }

    func removeCard(
        source: DuelCardSource,
        allowsReserved: Bool,
        playerIndex: Int,
        duel: inout DuelGameData
    ) throws -> DuelJewelCard {
        switch source {
        case let .market(cardID):
            for tier in 1 ... 3 {
                guard let index = duel.market[tier]?.firstIndex(where: { $0.id == cardID }) else { continue }
                let card = duel.market[tier]![index]
                if let replacement = duel.decks[tier]?.popLast() {
                    duel.market[tier]![index] = replacement
                } else {
                    duel.market[tier]!.remove(at: index)
                }
                return card
            }
        case let .deck(tier):
            guard (1 ... 3).contains(tier), let card = duel.decks[tier]?.popLast() else {
                throw GameRuleError.cardNotFound
            }
            return card
        case let .reserved(cardID):
            guard allowsReserved,
                  let index = duel.players[playerIndex].reservedCards.firstIndex(where: { $0.id == cardID })
            else { throw GameRuleError.invalidAction }
            return duel.players[playerIndex].reservedCards.remove(at: index)
        }
        throw GameRuleError.cardNotFound
    }

    func applyReturns(
        _ returning: [DuelTokenColor: Int],
        playerIndex: Int,
        duel: inout DuelGameData
    ) throws {
        guard returning.values.allSatisfy({ $0 >= 0 }),
              returning.allSatisfy({ duel.players[playerIndex].tokens[$0.key, default: 0] >= $0.value })
        else { throw GameRuleError.insufficientTokens }
        let excess = max(0, duel.players[playerIndex].tokenCount - DuelRules.tokenLimit)
        guard returning.values.reduce(0, +) == excess else { throw GameRuleError.tokenLimitViolation }
        for (color, count) in returning where count > 0 {
            duel.players[playerIndex].tokens[color, default: 0] -= count
            duel.bag.append(contentsOf: Array(repeating: color, count: count))
        }
    }

    func grantPrivilege(to playerIndex: Int, duel: inout DuelGameData) {
        guard duel.players[playerIndex].privileges < DuelRules.privilegeCount else { return }
        if duel.privilegesInPool > 0 {
            duel.privilegesInPool -= 1
            duel.players[playerIndex].privileges += 1
        } else {
            let opponent = opponentIndex(of: playerIndex)
            guard duel.players[opponent].privileges > 0 else { return }
            duel.players[opponent].privileges -= 1
            duel.players[playerIndex].privileges += 1
        }
    }

    func isStraightUninterruptedLine(_ indices: [Int]) -> Bool {
        guard !indices.isEmpty else { return false }
        if indices.count == 1 { return true }
        let coordinates = indices.map { ($0 / DuelRules.boardSize, $0 % DuelRules.boardSize) }
        let directions = [(0, 1), (1, 0), (1, 1), (1, -1)]
        return directions.contains { dr, dc in
            coordinates.contains { start in
                let expected = (0 ..< coordinates.count).map { step in
                    (start.0 + step * dr, start.1 + step * dc)
                }
                return expected.allSatisfy { point in coordinates.contains(where: { $0 == point }) }
            }
        }
    }

    func completeTurn(extraTurn: Bool, state: inout GameState) {
        guard let duel = state.duel else { return }
        let player = duel.players[state.currentPlayerIndex]
        if player.prestige >= DuelRules.targetPrestige
            || player.crowns >= DuelRules.targetCrowns
            || player.topColorPrestige >= DuelRules.targetColorPrestige {
            finishGame(winnerIndex: state.currentPlayerIndex, state: &state)
            return
        }
        state.duel?.turnStage = .privilegesAvailable
        if !extraTurn { advanceTurn(state: &state) }
        skipDisconnectedPlayers(in: &state)
    }

    func advanceTurn(state: inout GameState) {
        state.currentPlayerIndex = opponentIndex(of: state.currentPlayerIndex)
        if state.currentPlayerIndex == state.startingPlayerIndex { state.roundNumber += 1 }
    }

    func finishGame(winnerIndex: Int, state: inout GameState) {
        guard let duel = state.duel else { return }
        state.status = .finished
        let winnerID = state.players[winnerIndex].id
        if state.players[winnerIndex].kind == .human,
           state.players[opponentIndex(of: winnerIndex)].kind == .human {
            state.players[winnerIndex].medalCount += 1
        }
        let standings = state.players.indices.map { index in
            let player = duel.players[index]
            return GameResult.Standing(
                playerID: state.players[index].id,
                nickname: state.players[index].nickname,
                prestige: player.prestige,
                developmentCards: player.purchasedCards.count,
                rank: index == winnerIndex ? 1 : 2,
                isWinner: index == winnerIndex
            )
        }.sorted { $0.rank < $1.rank }
        state.result = GameResult(standings: standings, winnerIDs: [winnerID])
    }

    func opponentIndex(of index: Int) -> Int { index == 0 ? 1 : 0 }
}

private struct DuelRandomGenerator: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    init(rawState: UInt64) { state = rawState }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}
