import Foundation

/// Heuristic AI for standard (2–7 player) Splendor.
///
/// Strategy: enumerate a broad set of candidate actions (takes, reserves,
/// purchases), keep only those the ruleset accepts, then score the resulting
/// board with a weighted heuristic. The `hard` tier additionally runs a one-ply
/// look-ahead against the next opponent's best reply.
struct StandardBot: BotController {
    private let engine = RulesEngine()

    func chooseAction(state: GameState, playerID: UUID, difficulty: BotDifficulty) -> GameAction {
        guard state.currentPlayer.id == playerID else { return .pass }
        let profile = BotProfile.profile(for: difficulty)
        var rng = BotRNG(seed: UInt64(truncatingIfNeeded: state.revision)
            &+ UInt64(state.currentPlayerIndex &+ 1) &* 0x9E37_79B9)

        var candidates = validatedCandidates(state, meID: playerID)
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

    private func validatedCandidates(_ state: GameState, meID: UUID) -> [BotSelection.Candidate] {
        rawActions(for: state).compactMap { action in
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

    private func rawActions(for state: GameState) -> [GameAction] {
        let me = state.currentPlayer
        var actions: [GameAction] = []
        let demand = colorDemand(for: me, in: state)

        // Takes -------------------------------------------------------------
        let available = GemColor.purchasableColors.filter { state.bank[$0, default: 0] > 0 }
        for combo in distinctCombinations(available, upTo: 3) {
            let picks = Dictionary(uniqueKeysWithValues: combo.map { ($0, 1) })
            actions.append(makeTake(picks: picks, me: me, demand: demand))
        }
        for color in GemColor.purchasableColors where state.bank[color, default: 0] >= 4 {
            actions.append(makeTake(picks: [color: 2], me: me, demand: demand))
        }

        // Reserves ----------------------------------------------------------
        if me.reservedCards.count < 3, state.bank[.gold, default: 0] > 0 {
            for tier in 1 ... 3 {
                for card in state.market[tier] ?? [] {
                    actions.append(makeReserve(source: .market(cardID: card.id), me: me, demand: demand))
                }
                if !(state.decks[tier]?.isEmpty ?? true) {
                    actions.append(makeReserve(source: .deck(tier: tier), me: me, demand: demand))
                }
            }
        }

        // Purchases ---------------------------------------------------------
        var buyable: [(CardSource, DevelopmentCard)] = []
        for tier in 1 ... 3 {
            for card in state.market[tier] ?? [] { buyable.append((.market(cardID: card.id), card)) }
        }
        for card in me.reservedCards { buyable.append((.reserved(cardID: card.id), card)) }
        for (source, card) in buyable {
            guard let payment = payment(for: card, me: me) else { continue }
            let nobleID = chosenNoble(after: card, me: me, state: state)
            actions.append(.purchase(source: source, payment: payment, nobleID: nobleID))
        }

        return actions
    }

    private func makeTake(picks: [GemColor: Int], me: PlayerState, demand: [GemColor: Double]) -> GameAction {
        var projected = me.tokens
        for (color, amount) in picks { projected[color, default: 0] += amount }
        return .take(tokens: picks, returning: excessReturns(from: projected, demand: demand))
    }

    private func makeReserve(
        source: CardSource,
        me: PlayerState,
        demand: [GemColor: Double]
    ) -> GameAction {
        var projected = me.tokens
        projected[.gold, default: 0] += 1
        return .reserve(source: source, returning: excessReturns(from: projected, demand: demand))
    }

    /// Minimum-gold payment for a card, or `nil` when unaffordable.
    private func payment(for card: DevelopmentCard, me: PlayerState) -> [GemColor: Int]? {
        var payment: [GemColor: Int] = [:]
        var goldNeeded = 0
        for color in GemColor.purchasableColors {
            let required = max(0, card.cost[color, default: 0] - me.bonuses[color, default: 0])
            let colored = min(required, me.tokens[color, default: 0])
            if colored > 0 { payment[color] = colored }
            goldNeeded += required - colored
        }
        guard me.tokens[.gold, default: 0] >= goldNeeded else { return nil }
        if goldNeeded > 0 { payment[.gold] = goldNeeded }
        return payment
    }

    private func chosenNoble(after card: DevelopmentCard, me: PlayerState, state: GameState) -> String? {
        var bonuses = me.bonuses
        bonuses[card.bonus, default: 0] += 1
        let eligible = state.availableNobles.filter { noble in
            noble.requirement.allSatisfy { bonuses[$0.key, default: 0] >= $0.value }
        }
        guard eligible.count > 1 else { return nil }
        return eligible.max { lhs, rhs in
            lhs.prestige != rhs.prestige ? lhs.prestige < rhs.prestige : lhs.id > rhs.id
        }?.id
    }

    /// Chooses which tokens to hand back when over the 10-token cap. Drops the
    /// least-demanded colours first and keeps gold to the very end.
    private func excessReturns(from tokens: [GemColor: Int], demand: [GemColor: Double]) -> [GemColor: Int] {
        var excess = max(0, tokens.values.reduce(0, +) - 10)
        guard excess > 0 else { return [:] }
        let order = tokens.filter { $0.value > 0 }.keys.sorted { lhs, rhs in
            if lhs == .gold { return false }
            if rhs == .gold { return true }
            return demand[lhs, default: 0] < demand[rhs, default: 0]
        }
        var result: [GemColor: Int] = [:]
        for color in order where excess > 0 {
            let amount = min(excess, tokens[color, default: 0])
            if amount > 0 { result[color] = amount; excess -= amount }
        }
        return result
    }

    // MARK: - Evaluation

    private func evaluate(_ state: GameState, meID: UUID) -> Double {
        guard let me = state.players.first(where: { $0.id == meID }) else { return 0 }
        if state.status == .finished {
            let won = state.result?.winnerIDs.contains(meID) ?? false
            return won ? 1_000_000 : -1_000_000 + Double(me.prestige) * 100
        }

        var score = Double(me.prestige) * 100
        let demand = colorDemand(for: me, in: state)
        for color in GemColor.purchasableColors {
            let bonus = Double(me.bonuses[color, default: 0])
            score += bonus * (16 + min(demand[color, default: 0], 12) * 1.5)
        }
        // Permanent cards are the engine — reward building tempo directly.
        score += Double(me.purchasedCards.count) * 4
        // Tokens are flexible but with diminishing returns; hoarding is penalised.
        let colored = GemColor.purchasableColors.reduce(0) { $0 + me.tokens[$1, default: 0] }
        score += goldValue(me.tokens[.gold, default: 0])
        score += Double(colored) * 2.2
        if me.tokenCount >= 8 { score -= Double(me.tokenCount - 7) * 5 }
        // A reserve costs a slot and telegraphs intent; the value of the card it
        // holds already flows through `cardProgress`, so the raw count is a cost.
        score -= Double(me.reservedCards.count) * 2
        score += cardProgress(for: me, in: state)
        score += nobleProximity(for: me, in: state)

        let oppBest = state.players.filter { $0.id != meID }.map { Double($0.prestige) }.max() ?? 0
        score -= oppBest * 88
        if Double(me.prestige) >= Double(state.configuration.targetPrestige) - 2 { score += 40 }
        return score
    }

    /// Diminishing value of gold: the first few wildcards are flexible, a hoard is not.
    private func goldValue(_ gold: Int) -> Double {
        Double(min(gold, 3)) * 3.5 + Double(max(0, gold - 3)) * 1.2
    }

    /// One-ply look-ahead: after my move the next opponent plays the reply that is
    /// best *for them*; score the resulting position from my perspective. Modelling
    /// the opponent as optimising itself (rather than purely spiting me) avoids the
    /// paranoid hoarding that a strict worst-case min induces.
    private func scoreWithReply(_ state: GameState, meID: UUID) -> Double {
        guard state.status == .playing, state.currentPlayer.id != meID else {
            return evaluate(state, meID: meID)
        }
        let opponentID = state.currentPlayer.id
        var bestOpponentScore = -Double.greatestFiniteMagnitude
        var reply: GameState?
        for action in rawActions(for: state) {
            guard let result = simulate(action, state: state) else { continue }
            let opponentScore = evaluate(result, meID: opponentID)
            if opponentScore > bestOpponentScore {
                bestOpponentScore = opponentScore
                reply = result
            }
        }
        return evaluate(reply ?? state, meID: meID)
    }

    // MARK: - Heuristic helpers

    /// How much of each colour the player still needs across all obtainable cards.
    private func colorDemand(for me: PlayerState, in state: GameState) -> [GemColor: Double] {
        var demand: [GemColor: Double] = [:]
        var cards: [DevelopmentCard] = me.reservedCards
        for tier in 1 ... 3 { cards.append(contentsOf: state.market[tier] ?? []) }
        for card in cards {
            let weight = 1.0 + Double(card.prestige) * 0.4
            for color in GemColor.purchasableColors {
                let remaining = max(0, card.cost[color, default: 0] - me.bonuses[color, default: 0])
                demand[color, default: 0] += Double(remaining) * weight
            }
        }
        return demand
    }

    /// Rewards being close to affording cards. Uses a higher flat base so that
    /// progress toward even cheap engine cards competes with banking tokens, plus a
    /// concrete bonus for cards that can be bought right now, and counts the best
    /// two targets so a diversified position is valued.
    private func cardProgress(for me: PlayerState, in state: GameState) -> Double {
        var cards: [DevelopmentCard] = me.reservedCards
        for tier in 1 ... 3 { cards.append(contentsOf: state.market[tier] ?? []) }
        var values: [Double] = []
        for card in cards {
            var required = 0
            var covered = 0
            for color in GemColor.purchasableColors {
                let need = max(0, card.cost[color, default: 0] - me.bonuses[color, default: 0])
                required += need
                covered += min(need, me.tokens[color, default: 0])
            }
            let gold = me.tokens[.gold, default: 0]
            let effectiveCovered = min(required, covered + gold)
            let fraction = required == 0 ? 1.0 : Double(effectiveCovered) / Double(required)
            var value = fraction * fraction * (Double(card.prestige) * 5 + 16)
            if effectiveCovered >= required { value += 14 }
            values.append(value)
        }
        values.sort(by: >)
        return (values.first ?? 0) + (values.dropFirst().first ?? 0) * 0.4
    }

    /// Rewards proximity to claiming a noble tile.
    private func nobleProximity(for me: PlayerState, in state: GameState) -> Double {
        var score = 0.0
        for noble in state.availableNobles {
            var required = 0
            var covered = 0
            for (color, amount) in noble.requirement {
                required += amount
                covered += min(amount, me.bonuses[color, default: 0])
            }
            guard required > 0 else { continue }
            let fraction = Double(covered) / Double(required)
            score += fraction * fraction * Double(noble.prestige) * 22
        }
        return score
    }

    private func distinctCombinations(_ colors: [GemColor], upTo size: Int) -> [[GemColor]] {
        let target = min(size, colors.count)
        guard target > 0 else { return [] }
        var result: [[GemColor]] = []
        func recurse(start: Int, current: [GemColor]) {
            if current.count == target { result.append(current); return }
            for index in start ..< colors.count {
                recurse(start: index + 1, current: current + [colors[index]])
            }
        }
        recurse(start: 0, current: [])
        return result
    }
}
