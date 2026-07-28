import LuminoreCore
import SwiftUI

/// One guided tutorial step. `explain` steps advance when the learner taps "Next";
/// `action` steps advance automatically once `isSatisfied` becomes true for the
/// live snapshot (so they work regardless of the exact taps, including flows that
/// go through a sheet).
enum TutorialSurface: Equatable {
    case duelTokens
    case duelCards
}

struct TutorialStep<AnchorID: Hashable>: Identifiable {
    enum Kind {
        case explain
        /// Advances when the closure returns true for the current snapshot.
        case action((ClientGameSnapshot, UUID) -> Bool)
    }

    let id: Int
    let titleKey: String
    let bodyKey: String
    /// Board anchors to spotlight for this step (resolved against `GameAnchorKey`).
    let highlights: [AnchorID]
    /// Duel has separate token/card pages. Standard steps leave this `nil`.
    let surface: TutorialSurface?
    let kind: Kind

    init(
        id: Int,
        titleKey: String,
        bodyKey: String,
        highlights: [AnchorID],
        surface: TutorialSurface? = nil,
        kind: Kind
    ) {
        self.id = id
        self.titleKey = titleKey
        self.bodyKey = bodyKey
        self.highlights = highlights
        self.surface = surface
        self.kind = kind
    }

    var isAction: Bool {
        if case .action = kind { return true }
        return false
    }

    func isSatisfied(by snapshot: ClientGameSnapshot, localID: UUID) -> Bool {
        if case let .action(predicate) = kind { return predicate(snapshot, localID) }
        return false
    }
}

enum TutorialScript {
    /// The full standard-mode core-operations script. Baselines come from
    /// `TutorialScenario.standard` (6 pre-owned cards, 4 starting tokens).
    static func standard(localID: UUID) -> [TutorialStep<GameAnchorID>] {
        [
            TutorialStep(
                id: 0,
                titleKey: "tutorial.step.goal.title",
                bodyKey: "tutorial.step.goal.body",
                highlights: [.scoreLabel(localID)],
                kind: .explain
            ),
            TutorialStep(
                id: 1,
                titleKey: "tutorial.step.take.title",
                bodyKey: "tutorial.step.take.body",
                highlights: [.bankGem(.diamond), .bankGem(.sapphire), .bankGem(.emerald)],
                kind: .action { snapshot, id in Self.tokenCount(snapshot, id) >= 7 }
            ),
            TutorialStep(
                id: 2,
                titleKey: "tutorial.step.takeRules.title",
                bodyKey: "tutorial.step.takeRules.body",
                highlights: [.bankGem(.ruby)],
                kind: .action { snapshot, id in Self.tokenCount(snapshot, id, color: .ruby) >= 3 }
            ),
            TutorialStep(
                id: 3,
                titleKey: "tutorial.step.buy.title",
                bodyKey: "tutorial.step.buy.body",
                highlights: [.marketCard(TutorialScenario.affordableCardID)],
                kind: .action { snapshot, id in Self.purchasedCount(snapshot, id) >= 7 }
            ),
            TutorialStep(
                id: 4,
                titleKey: "tutorial.step.discount.title",
                bodyKey: "tutorial.step.discount.body",
                highlights: [.playerStack(localID, .diamond), .playerStack(localID, .sapphire)],
                kind: .explain
            ),
            TutorialStep(
                id: 5,
                titleKey: "tutorial.step.discountPurchase.title",
                bodyKey: "tutorial.step.discountPurchase.body",
                highlights: [.marketCard(TutorialScenario.permanentExampleCardID)],
                kind: .action { snapshot, id in Self.purchasedCount(snapshot, id) >= 8 }
            ),
            TutorialStep(
                id: 6,
                titleKey: "tutorial.step.reserve.title",
                bodyKey: "tutorial.step.reserve.body",
                highlights: [.marketCard(TutorialScenario.reserveTargetID)],
                kind: .action { snapshot, _ in snapshot.localReservedCards.count >= 1 }
            ),
            TutorialStep(
                id: 7,
                titleKey: "tutorial.step.gold.title",
                bodyKey: "tutorial.step.gold.body",
                highlights: [.playerStack(localID, .gold)],
                kind: .explain
            ),
            TutorialStep(
                id: 8,
                titleKey: "tutorial.step.noble.title",
                bodyKey: "tutorial.step.noble.body",
                highlights: [.nobleTile("tut-noble-1"), .marketCard(TutorialScenario.nobleTriggerCardID)],
                kind: .action { snapshot, id in Self.nobleCount(snapshot, id) >= 1 }
            ),
            TutorialStep(
                id: 9,
                titleKey: "tutorial.step.endgame.title",
                bodyKey: "tutorial.step.endgame.body",
                highlights: [.scoreLabel(localID)],
                kind: .explain
            )
        ]
    }

    static func duel(localID: UUID, opponentID: UUID) -> [TutorialStep<DuelAnchorID>] {
        [
            TutorialStep(
                id: 0,
                titleKey: "tutorial.duel.step.goal.title",
                bodyKey: "tutorial.duel.step.goal.body",
                highlights: [.victory(localID)],
                surface: .duelTokens,
                kind: .explain
            ),
            TutorialStep(
                id: 1,
                titleKey: "tutorial.duel.step.line.title",
                bodyKey: "tutorial.duel.step.line.body",
                highlights: TutorialScenario.duelFirstLine.map(DuelAnchorID.boardCell),
                surface: .duelTokens,
                kind: .action { snapshot, id in
                    guard snapshot.currentPlayerID == id,
                          let duel = snapshot.duel,
                          Self.duelTokenCount(Self.duelPlayer(duel, id)) >= 5
                    else { return false }
                    return Self.duelPlayer(duel, id)?.privileges ?? 0 >= 1
                }
            ),
            TutorialStep(
                id: 2,
                titleKey: "tutorial.duel.step.privilege.title",
                bodyKey: "tutorial.duel.step.privilege.body",
                highlights: [.privilegeControl, .boardCell(TutorialScenario.duelPrivilegeTargetIndex)],
                surface: .duelTokens,
                kind: .action { snapshot, id in
                    guard let player = snapshot.duel.flatMap({ Self.duelPlayer($0, id) }) else { return false }
                    return player.privileges == 0 && Self.duelTokenCount(player) >= 6
                }
            ),
            TutorialStep(
                id: 3,
                titleKey: "tutorial.duel.step.replenish.title",
                bodyKey: "tutorial.duel.step.replenish.body",
                highlights: [.replenishControl, .bag],
                surface: .duelTokens,
                kind: .action { snapshot, _ in
                    guard let duel = snapshot.duel else { return false }
                    return duel.bagCount == 0 && duel.turnStage == .mandatoryOnly
                }
            ),
            TutorialStep(
                id: 4,
                titleKey: "tutorial.duel.step.pearl.title",
                bodyKey: "tutorial.duel.step.pearl.body",
                highlights: TutorialScenario.duelPearlLine.map(DuelAnchorID.boardCell),
                surface: .duelTokens,
                kind: .action { snapshot, id in
                    guard snapshot.currentPlayerID == id,
                          let duel = snapshot.duel,
                          let player = Self.duelPlayer(duel, id),
                          let opponent = Self.duelPlayer(duel, opponentID)
                    else { return false }
                    return player.tokens[.pearl, default: 0] >= 2 && opponent.privileges >= 1
                }
            ),
            TutorialStep(
                id: 5,
                titleKey: "tutorial.duel.step.discount.title",
                bodyKey: "tutorial.duel.step.discount.body",
                highlights: [.marketCard(TutorialScenario.duelDoubleBonusCardID)],
                surface: .duelCards,
                kind: .action { snapshot, id in
                    snapshot.currentPlayerID == id
                        && Self.duelPlayer(snapshot.duel, id)?.purchasedCards.contains {
                            $0.id == TutorialScenario.duelDoubleBonusCardID
                        } == true
                }
            ),
            TutorialStep(
                id: 6,
                titleKey: "tutorial.duel.step.reserve.title",
                bodyKey: "tutorial.duel.step.reserve.body",
                highlights: [
                    .marketCard(TutorialScenario.duelReserveCardID),
                    .boardCell(TutorialScenario.duelGoldIndex),
                ],
                surface: .duelCards,
                kind: .action { snapshot, id in
                    snapshot.currentPlayerID == id
                        && snapshot.duel?.localReservedCards.contains {
                            $0.id == TutorialScenario.duelReserveCardID
                        } == true
                }
            ),
            TutorialStep(
                id: 7,
                titleKey: "tutorial.duel.step.gold.title",
                bodyKey: "tutorial.duel.step.gold.body",
                highlights: [.reserved(localID), .token(localID, .gold)],
                surface: .duelCards,
                kind: .action { snapshot, id in
                    snapshot.currentPlayerID == id
                        && Self.duelPlayer(snapshot.duel, id)?.purchasedCards.contains {
                            $0.id == TutorialScenario.duelReserveCardID
                        } == true
                }
            ),
            TutorialStep(
                id: 8,
                titleKey: "tutorial.duel.step.ability.title",
                bodyKey: "tutorial.duel.step.ability.body",
                highlights: [.marketCard(TutorialScenario.duelAbilityCardID)],
                surface: .duelCards,
                kind: .action { snapshot, id in
                    snapshot.currentPlayerID == id
                        && Self.duelPlayer(snapshot.duel, id)?.purchasedCards.contains {
                            $0.id == TutorialScenario.duelAbilityCardID
                        } == true
                }
            ),
            TutorialStep(
                id: 9,
                titleKey: "tutorial.duel.step.royal.title",
                bodyKey: "tutorial.duel.step.royal.body",
                highlights: [
                    .marketCard(TutorialScenario.duelCrownCardID),
                    .royal(TutorialScenario.duelRoyalID),
                ],
                surface: .duelCards,
                kind: .action { snapshot, id in
                    snapshot.currentPlayerID == id
                        && Self.duelPlayer(snapshot.duel, id)?.royalCards.contains {
                            $0.id == TutorialScenario.duelRoyalID
                        } == true
                }
            ),
            TutorialStep(
                id: 10,
                titleKey: "tutorial.duel.step.finish.title",
                bodyKey: "tutorial.duel.step.finish.body",
                highlights: [.victory(localID), .marketCard(TutorialScenario.duelFinalCardID)],
                surface: .duelCards,
                kind: .explain
            ),
        ]
    }

    private static func localPlayer(_ snapshot: ClientGameSnapshot, _ id: UUID) -> PublicPlayerSnapshot? {
        snapshot.players.first { $0.id == id }
    }

    private static func tokenCount(_ snapshot: ClientGameSnapshot, _ id: UUID) -> Int {
        localPlayer(snapshot, id)?.tokens.values.reduce(0, +) ?? 0
    }

    private static func tokenCount(
        _ snapshot: ClientGameSnapshot,
        _ id: UUID,
        color: GemColor
    ) -> Int {
        localPlayer(snapshot, id)?.tokens[color, default: 0] ?? 0
    }

    private static func purchasedCount(_ snapshot: ClientGameSnapshot, _ id: UUID) -> Int {
        localPlayer(snapshot, id)?.purchasedCards.count ?? 0
    }

    private static func nobleCount(_ snapshot: ClientGameSnapshot, _ id: UUID) -> Int {
        localPlayer(snapshot, id)?.nobles.count ?? 0
    }

    private static func duelPlayer(
        _ snapshot: DuelClientSnapshot?,
        _ id: UUID
    ) -> DuelPublicPlayerSnapshot? {
        snapshot?.players.first { $0.id == id }
    }

    private static func duelTokenCount(_ player: DuelPublicPlayerSnapshot?) -> Int {
        player?.tokens.values.reduce(0, +) ?? 0
    }
}
