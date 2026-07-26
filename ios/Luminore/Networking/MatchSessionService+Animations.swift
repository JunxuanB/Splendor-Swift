import Foundation
import LuminoreCore

extension MatchSessionService {
    func makeAnimationEvent(
        for action: GameAction,
        playerID: UUID,
        before: GameState,
        after: GameState
    ) -> GameAnimationEvent {
        let kind: GameAnimationEvent.Kind
        switch action {
        case let .take(tokens, _):
            kind = .take(tokens: tokens)
        case let .reserve(source, _):
            // A face-down deck reservation must stay secret. A formerly face-up
            // market card is safe to render because every player already saw it.
            let card: DevelopmentCard?
            if case let .market(cardID) = source {
                card = before.market.values.lazy.flatMap { $0 }.first { $0.id == cardID }
            } else {
                card = nil
            }
            kind = .reserve(source: source, card: card)
        case let .purchase(source, _, _):
            let oldPlayer = before.players.first { $0.id == playerID }
            let newPlayer = after.players.first { $0.id == playerID }
            let previousCardIDs = Set(oldPlayer?.purchasedCards.map(\.id) ?? [])
            let card = newPlayer?.purchasedCards.last { !previousCardIDs.contains($0.id) }
            let previousNobleIDs = Set(oldPlayer?.nobles.map(\.id) ?? [])
            let noble = newPlayer?.nobles.last { !previousNobleIDs.contains($0.id) }

            // A successful purchase always adds exactly one public development
            // card, so this fallback is only defensive for restored legacy data.
            let fallbackCard = before.market.values.lazy.flatMap { $0 }.first(where: { candidate in
                if case let .market(cardID) = source { return candidate.id == cardID }
                if case let .reserved(cardID) = source { return candidate.id == cardID }
                return false
            })
            guard let resolvedCard = card ?? fallbackCard ?? newPlayer?.purchasedCards.last else {
                return GameAnimationEvent(
                    revision: after.revision,
                    playerID: playerID,
                    kind: .pass
                )
            }
            kind = .purchase(source: source, card: resolvedCard, noble: noble)
        case .duel:
            // Duel views animate directly from authoritative board/card deltas.
            kind = .pass
        case .pass:
            kind = .pass
        }
        return GameAnimationEvent(
            revision: after.revision,
            playerID: playerID,
            kind: kind
        )
    }

    func scheduleGameBroadcast(after delay: TimeInterval, revision: Int, resetsTurnTimer: Bool = true) {
        animationBroadcastTask?.cancel()
        guard delay > 0 else {
            if resetsTurnTimer { scheduleTurnTimer() }
            broadcastGame()
            scheduleBotTurnIfNeeded()
            return
        }
        animationBroadcastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.authoritativeGame?.revision == revision else { return }
                if resetsTurnTimer { self.scheduleTurnTimer() }
                self.broadcastGame()
                self.scheduleBotTurnIfNeeded()
                self.animationBroadcastTask = nil
            }
        }
    }
}
