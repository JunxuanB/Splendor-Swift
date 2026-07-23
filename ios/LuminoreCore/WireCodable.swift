import Foundation

private enum WireKeys: String, CodingKey {
    case type
    case cardID
    case tier
    case tokens
    case returning
    case source
    case payment
    case nobleID
    case challenge
    case request
    case response
    case room
    case configuration
    case action
    case snapshot
    case message
    case paused
}

extension CardSource {
    private enum Kind: String, Codable { case market, deck, reserved }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: WireKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .market:
            self = .market(cardID: try container.decode(String.self, forKey: .cardID))
        case .deck:
            self = .deck(tier: try container.decode(Int.self, forKey: .tier))
        case .reserved:
            self = .reserved(cardID: try container.decode(String.self, forKey: .cardID))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: WireKeys.self)
        switch self {
        case let .market(cardID):
            try container.encode(Kind.market, forKey: .type)
            try container.encode(cardID, forKey: .cardID)
        case let .deck(tier):
            try container.encode(Kind.deck, forKey: .type)
            try container.encode(tier, forKey: .tier)
        case let .reserved(cardID):
            try container.encode(Kind.reserved, forKey: .type)
            try container.encode(cardID, forKey: .cardID)
        }
    }
}

extension GameAction {
    private enum Kind: String, Codable { case take, reserve, purchase, pass }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: WireKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .take:
            self = .take(
                tokens: try container.decode([GemColor: Int].self, forKey: .tokens),
                returning: try container.decode([GemColor: Int].self, forKey: .returning)
            )
        case .reserve:
            self = .reserve(
                source: try container.decode(CardSource.self, forKey: .source),
                returning: try container.decode([GemColor: Int].self, forKey: .returning)
            )
        case .purchase:
            self = .purchase(
                source: try container.decode(CardSource.self, forKey: .source),
                payment: try container.decode([GemColor: Int].self, forKey: .payment),
                nobleID: try container.decodeIfPresent(String.self, forKey: .nobleID)
            )
        case .pass:
            self = .pass
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: WireKeys.self)
        switch self {
        case let .take(tokens, returning):
            try container.encode(Kind.take, forKey: .type)
            try container.encode(tokens, forKey: .tokens)
            try container.encode(returning, forKey: .returning)
        case let .reserve(source, returning):
            try container.encode(Kind.reserve, forKey: .type)
            try container.encode(source, forKey: .source)
            try container.encode(returning, forKey: .returning)
        case let .purchase(source, payment, nobleID):
            try container.encode(Kind.purchase, forKey: .type)
            try container.encode(source, forKey: .source)
            try container.encode(payment, forKey: .payment)
            try container.encodeIfPresent(nobleID, forKey: .nobleID)
        case .pass:
            try container.encode(Kind.pass, forKey: .type)
        }
    }
}

extension NetworkMessage {
    private enum Kind: String, Codable {
        case challenge
        case join
        case joinResponse
        case room
        case updateConfiguration
        case enterConfiguration
        case startGame
        case action
        case gameState
        case returnToConfiguration
        case leave
        case setPaused
        case sessionSuspended
        case error
        case ping
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: WireKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .challenge: self = .challenge(try container.decode(AuthChallenge.self, forKey: .challenge))
        case .join: self = .join(try container.decode(JoinRequest.self, forKey: .request))
        case .joinResponse: self = .joinResponse(try container.decode(JoinResponse.self, forKey: .response))
        case .room: self = .room(try container.decode(RoomSnapshot.self, forKey: .room))
        case .updateConfiguration:
            self = .updateConfiguration(try container.decode(GameConfiguration.self, forKey: .configuration))
        case .enterConfiguration: self = .enterConfiguration
        case .startGame: self = .startGame
        case .action: self = .action(try container.decode(GameAction.self, forKey: .action))
        case .gameState: self = .gameState(try container.decode(ClientGameSnapshot.self, forKey: .snapshot))
        case .returnToConfiguration: self = .returnToConfiguration
        case .leave: self = .leave
        case .setPaused: self = .setPaused(try container.decode(Bool.self, forKey: .paused))
        case .sessionSuspended: self = .sessionSuspended
        case .error: self = .error(try container.decode(String.self, forKey: .message))
        case .ping: self = .ping
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: WireKeys.self)
        switch self {
        case let .challenge(challenge):
            try container.encode(Kind.challenge, forKey: .type)
            try container.encode(challenge, forKey: .challenge)
        case let .join(request):
            try container.encode(Kind.join, forKey: .type)
            try container.encode(request, forKey: .request)
        case let .joinResponse(response):
            try container.encode(Kind.joinResponse, forKey: .type)
            try container.encode(response, forKey: .response)
        case let .room(room):
            try container.encode(Kind.room, forKey: .type)
            try container.encode(room, forKey: .room)
        case let .updateConfiguration(configuration):
            try container.encode(Kind.updateConfiguration, forKey: .type)
            try container.encode(configuration, forKey: .configuration)
        case .enterConfiguration:
            try container.encode(Kind.enterConfiguration, forKey: .type)
        case .startGame:
            try container.encode(Kind.startGame, forKey: .type)
        case let .action(action):
            try container.encode(Kind.action, forKey: .type)
            try container.encode(action, forKey: .action)
        case let .gameState(snapshot):
            try container.encode(Kind.gameState, forKey: .type)
            try container.encode(snapshot, forKey: .snapshot)
        case .returnToConfiguration:
            try container.encode(Kind.returnToConfiguration, forKey: .type)
        case .leave:
            try container.encode(Kind.leave, forKey: .type)
        case let .setPaused(paused):
            try container.encode(Kind.setPaused, forKey: .type)
            try container.encode(paused, forKey: .paused)
        case .sessionSuspended:
            try container.encode(Kind.sessionSuspended, forKey: .type)
        case let .error(message):
            try container.encode(Kind.error, forKey: .type)
            try container.encode(message, forKey: .message)
        case .ping:
            try container.encode(Kind.ping, forKey: .type)
        }
    }
}
