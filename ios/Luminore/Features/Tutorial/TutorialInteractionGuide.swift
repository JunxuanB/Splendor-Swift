import LuminoreCore

/// Derives the standard board's enabled controls and spotlight targets from the
/// scripted interaction plus the learner's in-progress selection.
struct StandardTutorialInteractionGuide {
    let interaction: TutorialInteraction?
    let selectedGems: [GemColor: Int]

    var selectableGems: Set<GemColor>? {
        guard let interaction else { return nil }
        if case let .standardTake(requirement) = interaction { return Set(requirement.keys) }
        return []
    }

    var selectableCardIDs: Set<String>? {
        guard let interaction else { return nil }
        switch interaction {
        case let .standardPurchase(cardID), let .standardReserve(cardID): return [cardID]
        default: return []
        }
    }

    var selectableNobleIDs: Set<String>? { interaction == nil ? nil : [] }
    var canPass: Bool { interaction == nil }

    var canTakeSelection: Bool {
        guard let requirement = takeRequirement else { return interaction == nil }
        return selectedGems == requirement
    }

    func highlights(default defaultHighlights: [GameAnchorID]) -> [GameAnchorID] {
        guard let requirement = takeRequirement else { return defaultHighlights }
        if selectedGems == requirement { return [.takeControl] }
        return requirement.keys
            .filter { selectedGems[$0, default: 0] < requirement[$0, default: 0] }
            .sorted { $0.rawValue < $1.rawValue }
            .map(GameAnchorID.bankGem)
    }

    var actionHintKey: String {
        takeRequirement != nil && canTakeSelection
            ? "tutorial.hint.confirmTake"
            : "tutorial.hint.action"
    }

    func allowsGem(_ gem: GemColor) -> Bool {
        selectableGems?.contains(gem) ?? true
    }

    func allowsCard(_ cardID: String) -> Bool {
        selectableCardIDs?.contains(cardID) ?? true
    }

    func allowsPurchase(_ cardID: String) -> Bool {
        guard let interaction else { return true }
        if case let .standardPurchase(targetID) = interaction { return cardID == targetID }
        return false
    }

    func allowsReserve(_ cardID: String) -> Bool {
        guard let interaction else { return true }
        if case let .standardReserve(targetID) = interaction { return cardID == targetID }
        return false
    }

    private var takeRequirement: [GemColor: Int]? {
        guard let interaction, case let .standardTake(requirement) = interaction else { return nil }
        return requirement
    }
}

/// Equivalent interaction policy for the Duel board, including staged line takes
/// and the two-tap privilege flow.
struct DuelTutorialInteractionGuide {
    let interaction: TutorialInteraction?
    let selectedIndices: [Int]
    let privilegeMode: Bool

    var selectableBoardIndices: Set<Int>? {
        guard let interaction else { return nil }
        switch interaction {
        case let .duelTake(indices): return Set(indices)
        case let .duelSpendPrivilege(index): return privilegeMode ? [index] : []
        default: return []
        }
    }

    var canConfirmTake: Bool {
        guard let required = takeIndices else { return interaction == nil }
        return selectedIndices.count == required.count && Set(selectedIndices) == Set(required)
    }

    var canUsePrivilege: Bool {
        guard let interaction else { return true }
        if case .duelSpendPrivilege = interaction { return true }
        return false
    }

    var canReplenish: Bool { interaction == nil || interaction == .duelReplenish }
    var canSkipTurn: Bool { interaction == nil }

    var selectableCardIDs: Set<String>? {
        guard let interaction else { return nil }
        switch interaction {
        case let .duelPurchase(cardID), let .duelReserve(cardID, _): return [cardID]
        default: return []
        }
    }

    var selectableRoyalIDs: Set<String>? { interaction == nil ? nil : [] }

    var selectableGoldIndices: Set<Int>? {
        guard let interaction else { return nil }
        guard case let .duelReserve(_, goldBoardIndex) = interaction else { return [] }
        return [goldBoardIndex]
    }

    func highlights(default defaultHighlights: [DuelAnchorID]) -> [DuelAnchorID] {
        if let required = takeIndices {
            if canConfirmTake { return [.takeControl] }
            return required.filter { !selectedIndices.contains($0) }.map(DuelAnchorID.boardCell)
        }
        if let interaction, case let .duelSpendPrivilege(index) = interaction {
            return privilegeMode ? [.boardCell(index)] : [.privilegeControl]
        }
        return defaultHighlights
    }

    var actionHintKey: String {
        takeIndices != nil && canConfirmTake
            ? "tutorial.hint.confirmTake"
            : "tutorial.hint.action"
    }

    func allowsCard(_ cardID: String) -> Bool {
        guard let interaction else { return true }
        switch interaction {
        case let .duelPurchase(targetID), let .duelReserve(targetID, _),
             let .duelPurchaseReserved(targetID):
            return cardID == targetID
        default:
            return false
        }
    }

    func allowsPurchase(_ cardID: String) -> Bool {
        guard let interaction else { return true }
        switch interaction {
        case let .duelPurchase(targetID), let .duelPurchaseReserved(targetID):
            return cardID == targetID
        default:
            return false
        }
    }

    func allowsReserve(_ cardID: String?, goldBoardIndex: Int) -> Bool {
        guard let interaction else { return true }
        guard case let .duelReserve(targetID, targetGoldIndex) = interaction else { return false }
        return cardID == targetID && goldBoardIndex == targetGoldIndex
    }

    private var takeIndices: [Int]? {
        guard let interaction, case let .duelTake(indices) = interaction else { return nil }
        return indices
    }
}
