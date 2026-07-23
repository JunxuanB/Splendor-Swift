import Foundation

public enum GemColor: String, CaseIterable, Codable, CodingKeyRepresentable, Hashable, Identifiable, Sendable {
    case diamond
    case sapphire
    case emerald
    case ruby
    case onyx
    case gold

    public var id: String { rawValue }
    public static var purchasableColors: [GemColor] { allCases.filter { $0 != .gold } }
}

public enum PlayerKind: String, Codable, Sendable {
    case human
    case bot
}

public enum BotDifficulty: String, CaseIterable, Codable, Sendable {
    case easy
    case normal
    case hard
}

public struct Participant: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var nickname: String
    public var kind: PlayerKind
    public var isHost: Bool
    public var isConnected: Bool

    public init(
        id: UUID,
        nickname: String,
        kind: PlayerKind = .human,
        isHost: Bool = false,
        isConnected: Bool = true
    ) {
        self.id = id
        self.nickname = nickname
        self.kind = kind
        self.isHost = isHost
        self.isConnected = isConnected
    }
}

public enum GameMode: String, CaseIterable, Codable, Sendable {
    case standard
    case silkRoad
    case duel

    public var isAvailable: Bool { self == .standard }
}

public struct GameConfiguration: Codable, Equatable, Sendable {
    public var mode: GameMode
    public var targetPrestige: Int
    public var turnDurationSeconds: Int?
    public var turnGracePeriodEnabled: Bool

    public init(
        mode: GameMode = .standard,
        targetPrestige: Int = 15,
        turnDurationSeconds: Int? = 30,
        turnGracePeriodEnabled: Bool = true
    ) {
        self.mode = mode
        self.targetPrestige = min(max(targetPrestige, 10), 30)
        self.turnGracePeriodEnabled = turnGracePeriodEnabled
        if let turnDurationSeconds {
            self.turnDurationSeconds = min(max(turnDurationSeconds, 10), 120)
        } else {
            self.turnDurationSeconds = nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case mode
        case targetPrestige
        case turnDurationSeconds
        case turnGracePeriodEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            mode: try container.decode(GameMode.self, forKey: .mode),
            targetPrestige: try container.decode(Int.self, forKey: .targetPrestige),
            turnDurationSeconds: try container.decodeIfPresent(Int.self, forKey: .turnDurationSeconds),
            turnGracePeriodEnabled: try container.decodeIfPresent(Bool.self, forKey: .turnGracePeriodEnabled) ?? true
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mode, forKey: .mode)
        try container.encode(targetPrestige, forKey: .targetPrestige)
        try container.encodeIfPresent(turnDurationSeconds, forKey: .turnDurationSeconds)
        try container.encode(turnGracePeriodEnabled, forKey: .turnGracePeriodEnabled)
    }
}

public struct DevelopmentCard: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let tier: Int
    public let prestige: Int
    public let bonus: GemColor
    public let cost: [GemColor: Int]

    public init(id: String, tier: Int, prestige: Int, bonus: GemColor, cost: [GemColor: Int]) {
        self.id = id
        self.tier = tier
        self.prestige = prestige
        self.bonus = bonus
        self.cost = cost.filter { $0.value > 0 }
    }
}

public struct NobleTile: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let prestige: Int
    public let requirement: [GemColor: Int]

    public init(id: String, prestige: Int = 3, requirement: [GemColor: Int]) {
        self.id = id
        self.prestige = prestige
        self.requirement = requirement.filter { $0.value > 0 }
    }
}

public struct PlayerState: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var nickname: String
    public var kind: PlayerKind
    public var isConnected: Bool
    public var tokens: [GemColor: Int]
    public var purchasedCards: [DevelopmentCard]
    public var reservedCards: [DevelopmentCard]
    public var nobles: [NobleTile]

    public init(participant: Participant) {
        id = participant.id
        nickname = participant.nickname
        kind = participant.kind
        isConnected = participant.isConnected
        tokens = [:]
        purchasedCards = []
        reservedCards = []
        nobles = []
    }

    public var prestige: Int {
        purchasedCards.reduce(0) { $0 + $1.prestige } + nobles.reduce(0) { $0 + $1.prestige }
    }

    public var tokenCount: Int { tokens.values.reduce(0, +) }
    public var developmentCardCount: Int { purchasedCards.count }

    public var bonuses: [GemColor: Int] {
        Dictionary(grouping: purchasedCards, by: \DevelopmentCard.bonus)
            .mapValues(\.count)
    }

    /// Returns a copy of this seat rebound to a different account identity while
    /// preserving all in-game progress (tokens, cards, nobles). Used when resuming a
    /// saved match and a substitute takes over an absent player's seat.
    public func reseated(as newID: UUID, nickname newNickname: String) -> PlayerState {
        var copy = PlayerState(participant: Participant(
            id: newID,
            nickname: newNickname,
            kind: kind,
            isConnected: true
        ))
        copy.tokens = tokens
        copy.purchasedCards = purchasedCards
        copy.reservedCards = reservedCards
        copy.nobles = nobles
        return copy
    }
}

public enum MatchStatus: String, Codable, Sendable {
    case playing
    case finished
}

public struct GameResult: Codable, Equatable, Sendable {
    public struct Standing: Identifiable, Codable, Equatable, Sendable {
        public let playerID: UUID
        public let nickname: String
        public let prestige: Int
        public let developmentCards: Int
        public let rank: Int
        public let isWinner: Bool

        public var id: UUID { playerID }
    }

    public let standings: [Standing]
    public let winnerIDs: [UUID]
}

public struct GameState: Codable, Equatable, Sendable {
    public let gameID: UUID
    public let configuration: GameConfiguration
    public var players: [PlayerState]
    public var bank: [GemColor: Int]
    public var decks: [Int: [DevelopmentCard]]
    public var market: [Int: [DevelopmentCard]]
    public var availableNobles: [NobleTile]
    public var currentPlayerIndex: Int
    public let startingPlayerIndex: Int
    public var roundNumber: Int
    public var finalRoundTriggered: Bool
    public var status: MatchStatus
    public var result: GameResult?
    public var revision: Int

    public var currentPlayer: PlayerState { players[currentPlayerIndex] }
}

public enum CardSource: Codable, Equatable, Sendable {
    case market(cardID: String)
    case deck(tier: Int)
    case reserved(cardID: String)
}

public enum GameAction: Codable, Equatable, Sendable {
    case take(tokens: [GemColor: Int], returning: [GemColor: Int])
    case reserve(source: CardSource, returning: [GemColor: Int])
    case purchase(source: CardSource, payment: [GemColor: Int], nobleID: String?)
    case pass
}

public struct PublicPlayerSnapshot: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let nickname: String
    public let kind: PlayerKind
    public let isConnected: Bool
    public let tokens: [GemColor: Int]
    public let purchasedCards: [DevelopmentCard]
    public let reservedCardCount: Int
    public let nobles: [NobleTile]
    public let prestige: Int
}

public struct ClientGameSnapshot: Codable, Equatable, Sendable {
    public let gameID: UUID
    public let configuration: GameConfiguration
    public let players: [PublicPlayerSnapshot]
    public let localReservedCards: [DevelopmentCard]
    public let bank: [GemColor: Int]
    public let deckCounts: [Int: Int]
    public let market: [Int: [DevelopmentCard]]
    public let availableNobles: [NobleTile]
    public let currentPlayerID: UUID
    public let startingPlayerID: UUID
    public let turnDeadline: Date?
    public let roundNumber: Int
    public let status: MatchStatus
    public let result: GameResult?
    public let revision: Int
}

public extension GameState {
    func snapshot(for playerID: UUID, turnDeadline: Date? = nil) -> ClientGameSnapshot {
        ClientGameSnapshot(
            gameID: gameID,
            configuration: configuration,
            players: players.map {
                PublicPlayerSnapshot(
                    id: $0.id,
                    nickname: $0.nickname,
                    kind: $0.kind,
                    isConnected: $0.isConnected,
                    tokens: $0.tokens,
                    purchasedCards: $0.purchasedCards,
                    reservedCardCount: $0.reservedCards.count,
                    nobles: $0.nobles,
                    prestige: $0.prestige
                )
            },
            localReservedCards: players.first(where: { $0.id == playerID })?.reservedCards ?? [],
            bank: bank,
            deckCounts: decks.mapValues(\.count),
            market: market,
            availableNobles: availableNobles,
            currentPlayerID: currentPlayer.id,
            startingPlayerID: players[startingPlayerIndex].id,
            turnDeadline: turnDeadline,
            roundNumber: roundNumber,
            status: status,
            result: result,
            revision: revision
        )
    }
}
