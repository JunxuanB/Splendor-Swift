import Foundation

/// Heuristic AI for Splendor Duel (双人版).
///
/// A Duel turn is: optional privilege spends / replenish, then one mandatory
/// action (take / reserve / purchase). The driver re-invokes `chooseAction` while
/// the bot is still the current player, so this returns one action per call and
/// makes guaranteed progress toward a turn-ending mandatory action. Purchases
/// carry many choices (wild colour, abilities, royals); rather than re-derive
/// their legality, every candidate is validated by simulating it through the real
/// `DuelRuleset` and only accepted if it applies cleanly.
struct DuelBot: BotController {
    private let engine = RulesEngine()
    private let boardSize = DuelRules.boardSize

    func chooseAction(state: GameState, playerID: UUID, difficulty: BotDifficulty) -> GameAction {
        guard let duel = state.duel, state.currentPlayer.id == playerID,
              let meIndex = state.players.firstIndex(where: { $0.id == playerID })
        else { return .pass }
        let profile = BotProfile.profile(for: difficulty)
        var rng = BotRNG(seed: UInt64(truncatingIfNeeded: state.revision)
            &+ UInt64(meIndex &+ 1) &* 0x9E37_79B9)

        // Optional pre-actions (only while privileges are still available).
        if duel.turnStage == .privilegesAvailable {
            if duel.players[meIndex].privileges > 0,
               let index = beneficialPrivilegeSpend(duel: duel, meIndex: meIndex) {
                return .duel(.spendPrivilege(boardIndex: index))
            }
            // Refill the board from the bag when a fresh board would yield a clearly
            // better move than the current one. The cost of replenishing (the
            // opponent gains a privilege) is already reflected in the compared
            // scores, so this fires when the board is genuinely poor — including
            // when nothing is currently takeable/affordable at all.
            if !duel.bag.isEmpty, shouldReplenish(state: state, meID: playerID) {
                return .duel(.replenish)
            }
        }

        var candidates = validatedMandatory(state, meID: playerID)
        guard !candidates.isEmpty else { return .pass }

        if profile.opponentReply {
            candidates.sort { $0.baseScore > $1.baseScore }
            let deepened = candidates.prefix(6).map { candidate -> BotSelection.Candidate in
                let score = scoreWithReply(candidate.result, meID: playerID)
                return BotSelection.Candidate(action: candidate.action, result: candidate.result, baseScore: score)
            }
            candidates = deepened + candidates.dropFirst(6)
        }

        return BotSelection.choose(candidates, profile: profile, rng: &rng)
    }

    // MARK: - Candidate generation

    private func validatedMandatory(_ state: GameState, meID: UUID) -> [BotSelection.Candidate] {
        rawMandatory(for: state).compactMap { action in
            guard let result = simulate(action, state: state) else { return nil }
            return BotSelection.Candidate(action: action, result: result, baseScore: evaluate(result, meID: meID))
        }
    }

    private func simulate(_ action: GameAction, state: GameState) -> GameState? {
        var copy = state
        do {
            try engine.apply(action, playerID: state.currentPlayer.id, to: &copy)
            return copy
        } catch {
            return nil
        }
    }

    /// Whether refilling the board now improves our best available move enough to
    /// justify it. Replenishing is deterministic given the game's random state, so
    /// simulating it yields exactly the board we would draw.
    private func shouldReplenish(state: GameState, meID: UUID) -> Bool {
        let now = bestMandatoryScore(state, meID: meID)
        guard let replenished = simulate(.duel(.replenish), state: state) else { return false }
        let after = bestMandatoryScore(replenished, meID: meID)
        return after > now + 5
    }

    private func bestMandatoryScore(_ state: GameState, meID: UUID) -> Double {
        validatedMandatory(state, meID: meID).map(\.baseScore).max() ?? -Double.greatestFiniteMagnitude
    }

    private func rawMandatory(for state: GameState) -> [GameAction] {
        guard let duel = state.duel,
              let meIndex = state.players.firstIndex(where: { $0.id == state.currentPlayer.id })
        else { return [] }
        let me = duel.players[meIndex]
        let demand = colorDemand(for: me, duel: duel)
        var actions: [GameAction] = []

        // Takes: every straight line of 1–3 non-gold tokens on the board.
        for line in tokenLines(on: duel.board) {
            var projected = me.tokens
            for index in line {
                if let color = duel.board[index] { projected[color, default: 0] += 1 }
            }
            actions.append(.duel(.take(boardIndices: line, returning: excessReturns(from: projected, demand: demand))))
        }

        // Reserves: need a gold on the board and a free reserve slot.
        if me.reservedCards.count < DuelRules.reserveLimit,
           let goldIndex = duel.board.firstIndex(of: .gold) {
            var projected = me.tokens
            projected[.gold, default: 0] += 1
            let returning = excessReturns(from: projected, demand: demand)
            for tier in 1 ... 3 {
                for card in duel.market[tier] ?? [] {
                    actions.append(.duel(.reserve(goldBoardIndex: goldIndex, source: .market(cardID: card.id), returning: returning)))
                }
                if !(duel.decks[tier]?.isEmpty ?? true) {
                    actions.append(.duel(.reserve(goldBoardIndex: goldIndex, source: .deck(tier: tier), returning: returning)))
                }
            }
        }

        // Purchases: affordable market and reserved cards.
        var buyable: [(DuelCardSource, DuelJewelCard)] = []
        for tier in 1 ... 3 {
            for card in duel.market[tier] ?? [] { buyable.append((.market(cardID: card.id), card)) }
        }
        for card in me.reservedCards { buyable.append((.reserved(cardID: card.id), card)) }
        for (source, card) in buyable {
            guard let payment = payment(for: card, me: me) else { continue }
            actions.append(purchaseAction(source: source, card: card, payment: payment, me: me, duel: duel))
        }

        return actions
    }

    private func purchaseAction(
        source: DuelCardSource,
        card: DuelJewelCard,
        payment: [DuelTokenColor: Int],
        me: DuelPlayerState,
        duel: DuelGameData
    ) -> GameAction {
        var choices = DuelPurchaseChoices()

        // Wild bonus cards must be assigned an already-owned colour.
        if card.isWildBonus {
            choices.wildBonusColor = me.bonuses.filter { $0.value > 0 }
                .max { $0.value < $1.value }?.key ?? DuelGemColor.allCases.first
        }

        let effectiveColor = card.isWildBonus ? choices.wildBonusColor : card.bonusColor
        switch card.ability {
        case .takeMatchingToken:
            if let color = effectiveColor {
                let token = DuelTokenColor(color)
                choices.abilityBoardIndex = duel.board.firstIndex(of: token)
            }
        case .stealToken:
            let opponent = duel.players[opponentIndex(of: me, in: duel)]
            choices.stolenToken = DuelTokenColor.boardTakeable
                .filter { opponent.tokens[$0, default: 0] > 0 }
                .max { tokenValue($0) < tokenValue($1) }
        case .extraTurn, .takePrivilege, nil:
            break
        }

        // Crossing 3 or 6 crowns claims a royal card.
        let newCrowns = me.crowns + card.crowns
        let crossed = (me.crowns < 3 && newCrowns >= 3) || (me.crowns < 6 && newCrowns >= 6)
        if crossed, let royal = duel.availableRoyals.max(by: { $0.prestige < $1.prestige }) {
            choices.royalID = royal.id
            if royal.ability == .stealToken {
                let opponent = duel.players[opponentIndex(of: me, in: duel)]
                choices.royalStolenToken = DuelTokenColor.boardTakeable
                    .filter { opponent.tokens[$0, default: 0] > 0 }
                    .max { tokenValue($0) < tokenValue($1) }
            }
        }

        var afterPayment = me.tokens
        for (color, amount) in payment { afterPayment[color, default: 0] -= amount }
        let returning = excessReturns(from: afterPayment, demand: colorDemand(for: me, duel: duel))
        return .duel(.purchase(source: source, payment: payment, choices: choices, returning: returning))
    }

    /// Minimum-gold payment for a Duel card, or `nil` when unaffordable.
    private func payment(for card: DuelJewelCard, me: DuelPlayerState) -> [DuelTokenColor: Int]? {
        var payment: [DuelTokenColor: Int] = [:]
        var goldNeeded = 0
        for token in DuelTokenColor.boardTakeable {
            let discount = token.gemColor.map { me.bonuses[$0, default: 0] } ?? 0
            let required = max(0, card.cost[token, default: 0] - discount)
            let paid = min(required, me.tokens[token, default: 0])
            if paid > 0 { payment[token] = paid }
            goldNeeded += required - paid
        }
        guard me.tokens[.gold, default: 0] >= goldNeeded else { return nil }
        if goldNeeded > 0 { payment[.gold] = goldNeeded }
        return payment
    }

    /// Spends a privilege only to grab a genuinely-needed token while below the cap.
    private func beneficialPrivilegeSpend(duel: DuelGameData, meIndex: Int) -> Int? {
        let me = duel.players[meIndex]
        guard me.tokenCount <= 8 else { return nil }
        let demand = colorDemand(for: me, duel: duel)
        var best: (index: Int, value: Double)?
        for index in duel.board.indices {
            guard let color = duel.board[index], color != .gold else { continue }
            let value = demand[color, default: 0] + tokenValue(color)
            guard value > 0 else { continue }
            if best == nil || value > best!.value { best = (index, value) }
        }
        return best?.index
    }

    private func excessReturns(from tokens: [DuelTokenColor: Int], demand: [DuelTokenColor: Double]) -> [DuelTokenColor: Int] {
        var excess = max(0, tokens.values.reduce(0, +) - DuelRules.tokenLimit)
        guard excess > 0 else { return [:] }
        let order = tokens.filter { $0.value > 0 }.keys.sorted { lhs, rhs in
            if lhs == .gold { return false }
            if rhs == .gold { return true }
            return demand[lhs, default: 0] < demand[rhs, default: 0]
        }
        var result: [DuelTokenColor: Int] = [:]
        for color in order where excess > 0 {
            let amount = min(excess, tokens[color, default: 0])
            if amount > 0 { result[color] = amount; excess -= amount }
        }
        return result
    }

    // MARK: - Evaluation

    private func evaluate(_ state: GameState, meID: UUID) -> Double {
        guard let duel = state.duel,
              let meIndex = state.players.firstIndex(where: { $0.id == meID })
        else { return 0 }
        if state.status == .finished {
            return (state.result?.winnerIDs.contains(meID) ?? false) ? 1_000_000 : -1_000_000
        }
        let me = duel.players[meIndex]
        let opp = duel.players[opponentIndex(of: me, in: duel)]
        return standing(for: me, duel: duel) - standing(for: opp, duel: duel) * 0.95
    }

    /// Absolute strength of one Duel seat toward any of the three win conditions.
    private func standing(for player: DuelPlayerState, duel: DuelGameData) -> Double {
        var score = Double(player.prestige) * 100
        score += Double(player.crowns) * 35
        if player.crowns >= 3 { score += 40 }
        if player.crowns >= 6 { score += 60 }
        if player.crowns >= 8 { score += 80 }
        let topColor = player.topColorPrestige
        score += Double(topColor) * 30
        if topColor >= 8 { score += 60 }

        let demand = colorDemand(for: player, duel: duel)
        for (color, amount) in player.bonuses {
            score += Double(amount) * (14 + min(demand[DuelTokenColor(color), default: 0], 12) * 1.5)
        }
        score += Double(min(player.tokens[.gold, default: 0], 3)) * 4
            + Double(max(0, player.tokens[.gold, default: 0] - 3)) * 1.2
        score += Double(player.tokenCount) * 1.5
        score += Double(player.privileges) * 9
        // The held card's worth flows through `colorDemand`/prestige once bought;
        // the raw reserved slot is only mild option value, not a banking reward.
        score += Double(player.reservedCards.count) * 2
        if player.prestige >= DuelRules.targetPrestige - 3 { score += 60 }
        return score
    }

    /// One-ply look-ahead: the opponent plays the reply best *for them*; score the
    /// resulting position from my perspective (see the note in `StandardBot`).
    private func scoreWithReply(_ state: GameState, meID: UUID) -> Double {
        guard state.status == .playing, state.currentPlayer.id != meID else {
            return evaluate(state, meID: meID)
        }
        let opponentID = state.currentPlayer.id
        var bestOpponentScore = -Double.greatestFiniteMagnitude
        var reply: GameState?
        for candidate in validatedMandatory(state, meID: opponentID) {
            let opponentScore = evaluate(candidate.result, meID: opponentID)
            if opponentScore > bestOpponentScore {
                bestOpponentScore = opponentScore
                reply = candidate.result
            }
        }
        return evaluate(reply ?? state, meID: meID)
    }

    // MARK: - Helpers

    private func colorDemand(for player: DuelPlayerState, duel: DuelGameData) -> [DuelTokenColor: Double] {
        var demand: [DuelTokenColor: Double] = [:]
        var cards: [DuelJewelCard] = player.reservedCards
        for tier in 1 ... 3 { cards.append(contentsOf: duel.market[tier] ?? []) }
        for card in cards {
            let weight = 1.0 + Double(card.prestige) * 0.4 + Double(card.crowns) * 0.6
            for token in DuelTokenColor.boardTakeable {
                let discount = token.gemColor.map { player.bonuses[$0, default: 0] } ?? 0
                let remaining = max(0, card.cost[token, default: 0] - discount)
                demand[token, default: 0] += Double(remaining) * weight
            }
        }
        return demand
    }

    private func tokenValue(_ token: DuelTokenColor) -> Double {
        switch token {
        case .gold: 3
        case .pearl: 2
        default: 1
        }
    }

    private func opponentIndex(of player: DuelPlayerState, in duel: DuelGameData) -> Int {
        (duel.players.firstIndex(where: { $0.id == player.id }) ?? 0) == 0 ? 1 : 0
    }

    /// All distinct straight lines of length 1–3 made of non-gold board tokens.
    private func tokenLines(on board: [DuelTokenColor?]) -> [[Int]] {
        let directions = [(0, 1), (1, 0), (1, 1), (1, -1)]
        var seen = Set<[Int]>()
        var lines: [[Int]] = []
        for row in 0 ..< boardSize {
            for col in 0 ..< boardSize {
                for length in 1 ... 3 {
                    for (dRow, dCol) in directions {
                        var indices: [Int] = []
                        var valid = true
                        for step in 0 ..< length {
                            let r = row + step * dRow
                            let c = col + step * dCol
                            guard (0 ..< boardSize).contains(r), (0 ..< boardSize).contains(c) else { valid = false; break }
                            let index = r * boardSize + c
                            guard let token = board[index], token != .gold else { valid = false; break }
                            indices.append(index)
                        }
                        guard valid else { continue }
                        let key = indices.sorted()
                        if seen.insert(key).inserted { lines.append(indices) }
                        if length == 1 { break } // direction irrelevant for a single cell
                    }
                }
            }
        }
        return lines
    }
}
