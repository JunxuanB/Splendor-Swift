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
    public var medalCount: Int
    public var isHost: Bool
    public var isConnected: Bool

    public init(
        id: UUID,
        nickname: String,
        kind: PlayerKind = .human,
        medalCount: Int = 0,
        isHost: Bool = false,
        isConnected: Bool = true
    ) {
        self.id = id
        self.nickname = nickname
        self.kind = kind
        self.medalCount = max(0, medalCount)
        self.isHost = isHost
        self.isConnected = isConnected
    }

    private enum CodingKeys: String, CodingKey {
        case id, nickname, kind, medalCount, isHost, isConnected
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            nickname: try container.decode(String.self, forKey: .nickname),
            kind: try container.decodeIfPresent(PlayerKind.self, forKey: .kind) ?? .human,
            medalCount: try container.decodeIfPresent(Int.self, forKey: .medalCount) ?? 0,
            isHost: try container.decodeIfPresent(Bool.self, forKey: .isHost) ?? false,
            isConnected: try container.decodeIfPresent(Bool.self, forKey: .isConnected) ?? true
        )
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
    public var affordableCardHighlightEnabled: Bool

    public init(
        mode: GameMode = .standard,
        targetPrestige: Int = 15,
        turnDurationSeconds: Int? = 30,
        turnGracePeriodEnabled: Bool = true,
        affordableCardHighlightEnabled: Bool = true
    ) {
        self.mode = mode
        self.targetPrestige = min(max(targetPrestige, 10), 30)
        self.turnGracePeriodEnabled = turnGracePeriodEnabled
        self.affordableCardHighlightEnabled = affordableCardHighlightEnabled
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
        case affordableCardHighlightEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            mode: try container.decode(GameMode.self, forKey: .mode),
            targetPrestige: try container.decode(Int.self, forKey: .targetPrestige),
            turnDurationSeconds: try container.decodeIfPresent(Int.self, forKey: .turnDurationSeconds),
            turnGracePeriodEnabled: try container.decodeIfPresent(Bool.self, forKey: .turnGracePeriodEnabled) ?? true,
            affordableCardHighlightEnabled: try container.decodeIfPresent(
                Bool.self,
                forKey: .affordableCardHighlightEnabled
            ) ?? true
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mode, forKey: .mode)
        try container.encode(targetPrestige, forKey: .targetPrestige)
        try container.encodeIfPresent(turnDurationSeconds, forKey: .turnDurationSeconds)
        try container.encode(turnGracePeriodEnabled, forKey: .turnGracePeriodEnabled)
        try container.encode(affordableCardHighlightEnabled, forKey: .affordableCardHighlightEnabled)
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
    public var medalCount: Int
    public var isConnected: Bool
    public var tokens: [GemColor: Int]
    public var purchasedCards: [DevelopmentCard]
    public var reservedCards: [DevelopmentCard]
    public var nobles: [NobleTile]

    public init(participant: Participant) {
        id = participant.id
        nickname = participant.nickname
        kind = participant.kind
        medalCount = participant.medalCount
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

    private enum CodingKeys: String, CodingKey {
        case id, nickname, kind, medalCount, isConnected, tokens, purchasedCards, reservedCards, nobles
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        nickname = try container.decode(String.self, forKey: .nickname)
        kind = try container.decodeIfPresent(PlayerKind.self, forKey: .kind) ?? .human
        medalCount = max(0, try container.decodeIfPresent(Int.self, forKey: .medalCount) ?? 0)
        isConnected = try container.decodeIfPresent(Bool.self, forKey: .isConnected) ?? true
        tokens = try container.decodeIfPresent([GemColor: Int].self, forKey: .tokens) ?? [:]
        purchasedCards = try container.decodeIfPresent([DevelopmentCard].self, forKey: .purchasedCards) ?? []
        reservedCards = try container.decodeIfPresent([DevelopmentCard].self, forKey: .reservedCards) ?? []
        nobles = try container.decodeIfPresent([NobleTile].self, forKey: .nobles) ?? []
    }

    /// Returns a copy of this seat rebound to a different account identity while
    /// preserving all in-game progress (tokens, cards, nobles). Used when resuming a
    /// saved match and a substitute takes over an absent player's seat.
    public func reseated(as newID: UUID, nickname newNickname: String, medalCount newMedalCount: Int = 0) -> PlayerState {
        var copy = PlayerState(participant: Participant(
            id: newID,
            nickname: newNickname,
            kind: kind,
            medalCount: newMedalCount,
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

        public init(
            playerID: UUID,
            nickname: String,
            prestige: Int,
            developmentCards: Int,
            rank: Int,
            isWinner: Bool
        ) {
            self.playerID = playerID
            self.nickname = nickname
            self.prestige = prestige
            self.developmentCards = developmentCards
            self.rank = rank
            self.isWinner = isWinner
        }
    }

    public let standings: [Standing]
    public let winnerIDs: [UUID]
    public let finishedAt: Date

    public init(standings: [Standing], winnerIDs: [UUID], finishedAt: Date = Date()) {
        self.standings = standings
        self.winnerIDs = winnerIDs
        self.finishedAt = finishedAt
    }

    private enum CodingKeys: String, CodingKey {
        case standings, winnerIDs, finishedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        standings = try container.decode([Standing].self, forKey: .standings)
        winnerIDs = try container.decode([UUID].self, forKey: .winnerIDs)
        finishedAt = try container.decodeIfPresent(Date.self, forKey: .finishedAt) ?? Date()
    }
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
    public let medalCount: Int
    public let isConnected: Bool
    public let tokens: [GemColor: Int]
    public let purchasedCards: [DevelopmentCard]
    public let reservedCards: [DevelopmentCard]
    public let reservedCardCount: Int
    public let nobles: [NobleTile]
    public let prestige: Int

    private enum CodingKeys: String, CodingKey {
        case id
        case nickname
        case kind
        case medalCount
        case isConnected
        case tokens
        case purchasedCards
        case reservedCards
        case reservedCardCount
        case nobles
        case prestige
    }

    public init(
        id: UUID,
        nickname: String,
        kind: PlayerKind,
        medalCount: Int = 0,
        isConnected: Bool,
        tokens: [GemColor: Int],
        purchasedCards: [DevelopmentCard],
        reservedCards: [DevelopmentCard],
        reservedCardCount: Int,
        nobles: [NobleTile],
        prestige: Int
    ) {
        self.id = id
        self.nickname = nickname
        self.kind = kind
        self.medalCount = max(0, medalCount)
        self.isConnected = isConnected
        self.tokens = tokens
        self.purchasedCards = purchasedCards
        self.reservedCards = reservedCards
        self.reservedCardCount = reservedCardCount
        self.nobles = nobles
        self.prestige = prestige
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        nickname = try container.decode(String.self, forKey: .nickname)
        kind = try container.decode(PlayerKind.self, forKey: .kind)
        medalCount = max(0, try container.decodeIfPresent(Int.self, forKey: .medalCount) ?? 0)
        isConnected = try container.decode(Bool.self, forKey: .isConnected)
        tokens = try container.decode([GemColor: Int].self, forKey: .tokens)
        purchasedCards = try container.decode([DevelopmentCard].self, forKey: .purchasedCards)
        reservedCards = try container.decodeIfPresent([DevelopmentCard].self, forKey: .reservedCards) ?? []
        reservedCardCount = try container.decode(Int.self, forKey: .reservedCardCount)
        nobles = try container.decode([NobleTile].self, forKey: .nobles)
        prestige = try container.decode(Int.self, forKey: .prestige)
    }
}

/// Host-authored timing for the opening roulette. Every transport carries this
/// value inside the same game snapshot so all players reveal the same first seat.
public struct OpeningTurnSelection: Codable, Equatable, Sendable {
    public static let duration: TimeInterval = 5

    public let startedAt: Date
    public let endsAt: Date

    public init(startedAt: Date, endsAt: Date) {
        self.startedAt = startedAt
        self.endsAt = endsAt
    }

    public init(startedAt: Date = Date(), duration: TimeInterval = Self.duration) {
        self.init(startedAt: startedAt, endsAt: startedAt.addingTimeInterval(duration))
    }
}

/// Authoritative pause state, carried inside every game snapshot so that clients
/// reconcile it on each frame instead of relying on one-shot control messages
/// (which can be lost across a flaky reconnect). `nil` means the match is running.
public struct MatchPause: Codable, Equatable, Sendable {
    public enum Reason: String, Codable, Sendable {
        /// The host tapped pause.
        case host
        /// One or more players dropped mid-game; the whole match is frozen for a
        /// grace window so they can reconnect before their turns are skipped.
        case disconnect
    }

    public let reason: Reason
    /// When the disconnect grace window ends (for the countdown UI). `nil` for a
    /// host-initiated pause, which has no deadline.
    public let resumeDeadline: Date?
    /// Nicknames of the players the match is waiting on (disconnect pause only).
    public let waitingForNicknames: [String]

    public init(reason: Reason, resumeDeadline: Date? = nil, waitingForNicknames: [String] = []) {
        self.reason = reason
        self.resumeDeadline = resumeDeadline
        self.waitingForNicknames = waitingForNicknames
    }
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
    public let openingTurnSelection: OpeningTurnSelection?
    public let turnDeadline: Date?
    public let roundNumber: Int
    public let status: MatchStatus
    public let result: GameResult?
    public let revision: Int
    /// Authoritative pause state; `nil` when the match is running.
    public let pause: MatchPause?

    public init(
        gameID: UUID,
        configuration: GameConfiguration,
        players: [PublicPlayerSnapshot],
        localReservedCards: [DevelopmentCard],
        bank: [GemColor: Int],
        deckCounts: [Int: Int],
        market: [Int: [DevelopmentCard]],
        availableNobles: [NobleTile],
        currentPlayerID: UUID,
        startingPlayerID: UUID,
        openingTurnSelection: OpeningTurnSelection?,
        turnDeadline: Date?,
        roundNumber: Int,
        status: MatchStatus,
        result: GameResult?,
        revision: Int,
        pause: MatchPause? = nil
    ) {
        self.gameID = gameID
        self.configuration = configuration
        self.players = players
        self.localReservedCards = localReservedCards
        self.bank = bank
        self.deckCounts = deckCounts
        self.market = market
        self.availableNobles = availableNobles
        self.currentPlayerID = currentPlayerID
        self.startingPlayerID = startingPlayerID
        self.openingTurnSelection = openingTurnSelection
        self.turnDeadline = turnDeadline
        self.roundNumber = roundNumber
        self.status = status
        self.result = result
        self.revision = revision
        self.pause = pause
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gameID = try container.decode(UUID.self, forKey: .gameID)
        configuration = try container.decode(GameConfiguration.self, forKey: .configuration)
        players = try container.decode([PublicPlayerSnapshot].self, forKey: .players)
        localReservedCards = try container.decode([DevelopmentCard].self, forKey: .localReservedCards)
        bank = try container.decode([GemColor: Int].self, forKey: .bank)
        deckCounts = try container.decode([Int: Int].self, forKey: .deckCounts)
        market = try container.decode([Int: [DevelopmentCard]].self, forKey: .market)
        availableNobles = try container.decode([NobleTile].self, forKey: .availableNobles)
        currentPlayerID = try container.decode(UUID.self, forKey: .currentPlayerID)
        startingPlayerID = try container.decode(UUID.self, forKey: .startingPlayerID)
        openingTurnSelection = try container.decodeIfPresent(OpeningTurnSelection.self, forKey: .openingTurnSelection)
        turnDeadline = try container.decodeIfPresent(Date.self, forKey: .turnDeadline)
        roundNumber = try container.decode(Int.self, forKey: .roundNumber)
        status = try container.decode(MatchStatus.self, forKey: .status)
        result = try container.decodeIfPresent(GameResult.self, forKey: .result)
        revision = try container.decode(Int.self, forKey: .revision)
        pause = try container.decodeIfPresent(MatchPause.self, forKey: .pause)
    }
}

public extension GameState {
    func snapshot(
        for playerID: UUID,
        turnDeadline: Date? = nil,
        openingTurnSelection: OpeningTurnSelection? = nil,
        pause: MatchPause? = nil
    ) -> ClientGameSnapshot {
        ClientGameSnapshot(
            gameID: gameID,
            configuration: configuration,
            players: players.map {
                PublicPlayerSnapshot(
                    id: $0.id,
                    nickname: $0.nickname,
                    kind: $0.kind,
                    medalCount: $0.medalCount,
                    isConnected: $0.isConnected,
                    tokens: $0.tokens,
                    purchasedCards: $0.purchasedCards,
                    reservedCards: $0.reservedCards,
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
            openingTurnSelection: openingTurnSelection,
            turnDeadline: turnDeadline,
            roundNumber: roundNumber,
            status: status,
            result: result,
            revision: revision,
            pause: pause
        )
    }
}
