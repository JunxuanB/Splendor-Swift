import Foundation

public enum DuelGemColor: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case diamond
    case sapphire
    case emerald
    case ruby
    case onyx

    public var id: String { rawValue }
}

public enum DuelTokenColor: String, CaseIterable, Codable, CodingKeyRepresentable, Hashable, Identifiable, Sendable {
    case diamond
    case sapphire
    case emerald
    case ruby
    case onyx
    case pearl
    case gold

    public var id: String { rawValue }
    public static let boardTakeable: [Self] = allCases.filter { $0 != .gold }

    public init(_ gem: DuelGemColor) {
        self = Self(rawValue: gem.rawValue)!
    }

    public var gemColor: DuelGemColor? { DuelGemColor(rawValue: rawValue) }
}

public enum DuelCardAbility: String, Codable, Hashable, Sendable {
    case extraTurn
    case takeMatchingToken
    case takePrivilege
    case stealToken
}

public struct DuelJewelCard: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let tier: Int
    public let prestige: Int
    public let crowns: Int
    public let bonusColor: DuelGemColor?
    public let bonusAmount: Int
    public let isWildBonus: Bool
    public let cost: [DuelTokenColor: Int]
    public let ability: DuelCardAbility?

    public init(
        id: String,
        tier: Int,
        prestige: Int,
        crowns: Int,
        bonusColor: DuelGemColor?,
        bonusAmount: Int,
        isWildBonus: Bool = false,
        cost: [DuelTokenColor: Int],
        ability: DuelCardAbility? = nil
    ) {
        self.id = id
        self.tier = tier
        self.prestige = max(0, prestige)
        self.crowns = max(0, crowns)
        self.bonusColor = bonusColor
        self.bonusAmount = max(0, bonusAmount)
        self.isWildBonus = isWildBonus
        self.cost = cost.filter { $0.value > 0 }
        self.ability = ability
    }
}

public struct DuelOwnedCard: Identifiable, Codable, Hashable, Sendable {
    public let card: DuelJewelCard
    public let assignedWildColor: DuelGemColor?

    public var id: String { card.id }
    public var effectiveBonusColor: DuelGemColor? { card.isWildBonus ? assignedWildColor : card.bonusColor }
}

public struct DuelRoyalCard: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let prestige: Int
    public let ability: DuelCardAbility?

    public init(id: String, prestige: Int, ability: DuelCardAbility? = nil) {
        self.id = id
        self.prestige = max(0, prestige)
        self.ability = ability
    }
}

public struct DuelPlayerState: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var tokens: [DuelTokenColor: Int]
    public var purchasedCards: [DuelOwnedCard]
    public var reservedCards: [DuelJewelCard]
    public var royalCards: [DuelRoyalCard]
    public var privileges: Int

    public init(id: UUID) {
        self.id = id
        tokens = [:]
        purchasedCards = []
        reservedCards = []
        royalCards = []
        privileges = 0
    }

    public var tokenCount: Int { tokens.values.reduce(0, +) }
    public var prestige: Int {
        purchasedCards.reduce(0) { $0 + $1.card.prestige }
            + royalCards.reduce(0) { $0 + $1.prestige }
    }
    public var crowns: Int { purchasedCards.reduce(0) { $0 + $1.card.crowns } }
    public var bonuses: [DuelGemColor: Int] {
        var result: [DuelGemColor: Int] = [:]
        for owned in purchasedCards {
            if let color = owned.effectiveBonusColor {
                result[color, default: 0] += owned.card.bonusAmount
            }
        }
        return result
    }
    public var colorPrestige: [DuelGemColor: Int] {
        var result: [DuelGemColor: Int] = [:]
        for owned in purchasedCards {
            if let color = owned.effectiveBonusColor {
                result[color, default: 0] += owned.card.prestige
            }
        }
        return result
    }
    public var topColorPrestige: Int { colorPrestige.values.max() ?? 0 }
}

public enum DuelTurnStage: String, Codable, Sendable {
    case privilegesAvailable
    case mandatoryOnly
}

public struct DuelGameData: Codable, Equatable, Sendable {
    public var players: [DuelPlayerState]
    public var board: [DuelTokenColor?]
    public var bag: [DuelTokenColor]
    public var decks: [Int: [DuelJewelCard]]
    public var market: [Int: [DuelJewelCard]]
    public var availableRoyals: [DuelRoyalCard]
    public var privilegesInPool: Int
    public var turnStage: DuelTurnStage
    public var randomState: UInt64

    public init(
        players: [DuelPlayerState],
        board: [DuelTokenColor?],
        bag: [DuelTokenColor],
        decks: [Int: [DuelJewelCard]],
        market: [Int: [DuelJewelCard]],
        availableRoyals: [DuelRoyalCard],
        privilegesInPool: Int,
        turnStage: DuelTurnStage = .privilegesAvailable,
        randomState: UInt64
    ) {
        self.players = players
        self.board = board
        self.bag = bag
        self.decks = decks
        self.market = market
        self.availableRoyals = availableRoyals
        self.privilegesInPool = privilegesInPool
        self.turnStage = turnStage
        self.randomState = randomState
    }
}

public enum DuelCardSource: Codable, Equatable, Sendable {
    case market(cardID: String)
    case deck(tier: Int)
    case reserved(cardID: String)
}

public struct DuelPurchaseChoices: Codable, Equatable, Sendable {
    public var wildBonusColor: DuelGemColor?
    public var abilityBoardIndex: Int?
    public var stolenToken: DuelTokenColor?
    public var royalID: String?
    public var royalStolenToken: DuelTokenColor?

    public init(
        wildBonusColor: DuelGemColor? = nil,
        abilityBoardIndex: Int? = nil,
        stolenToken: DuelTokenColor? = nil,
        royalID: String? = nil,
        royalStolenToken: DuelTokenColor? = nil
    ) {
        self.wildBonusColor = wildBonusColor
        self.abilityBoardIndex = abilityBoardIndex
        self.stolenToken = stolenToken
        self.royalID = royalID
        self.royalStolenToken = royalStolenToken
    }
}

public enum DuelAction: Codable, Equatable, Sendable {
    case spendPrivilege(boardIndex: Int)
    case replenish
    case take(boardIndices: [Int], returning: [DuelTokenColor: Int])
    case reserve(goldBoardIndex: Int, source: DuelCardSource, returning: [DuelTokenColor: Int])
    case purchase(
        source: DuelCardSource,
        payment: [DuelTokenColor: Int],
        choices: DuelPurchaseChoices,
        returning: [DuelTokenColor: Int]
    )
}

public struct DuelPublicPlayerSnapshot: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let tokens: [DuelTokenColor: Int]
    public let purchasedCards: [DuelOwnedCard]
    public let royalCards: [DuelRoyalCard]
    public let reservedCardCount: Int
    public let privileges: Int
    public let prestige: Int
    public let crowns: Int
    public let bonuses: [DuelGemColor: Int]
    public let colorPrestige: [DuelGemColor: Int]
}

public struct DuelClientSnapshot: Codable, Equatable, Sendable {
    public let players: [DuelPublicPlayerSnapshot]
    public let localReservedCards: [DuelJewelCard]
    public let board: [DuelTokenColor?]
    public let bagCount: Int
    public let deckCounts: [Int: Int]
    public let market: [Int: [DuelJewelCard]]
    public let availableRoyals: [DuelRoyalCard]
    public let privilegesInPool: Int
    public let turnStage: DuelTurnStage
}

public enum DuelRules {
    public static let tokenLimit = 10
    public static let reserveLimit = 3
    public static let targetPrestige = 20
    public static let targetCrowns = 10
    public static let targetColorPrestige = 10
    public static let boardSize = 5
    public static let privilegeCount = 3
    public static let tokenSupply: [DuelTokenColor: Int] = [
        .diamond: 4, .sapphire: 4, .emerald: 4, .ruby: 4, .onyx: 4,
        .pearl: 2, .gold: 3,
    ]

    public static let spiralOrder: [Int] = [
        12, 17, 16, 11, 6, 7, 8, 13, 18, 23, 22, 21, 20,
        15, 10, 5, 0, 1, 2, 3, 4, 9, 14, 19, 24,
    ]
}
