import Foundation

public struct RoomDescriptor: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var hostNickname: String
    public var playerCount: Int
    public var maximumPlayers: Int
    public var isPasswordProtected: Bool
    public var stage: RoomStage

    public init(
        id: UUID,
        name: String,
        hostNickname: String,
        playerCount: Int,
        maximumPlayers: Int = 7,
        isPasswordProtected: Bool,
        stage: RoomStage = .lobby
    ) {
        self.id = id
        self.name = name
        self.hostNickname = hostNickname
        self.playerCount = playerCount
        self.maximumPlayers = maximumPlayers
        self.isPasswordProtected = isPasswordProtected
        self.stage = stage
    }
}

public enum RoomStage: String, Codable, Sendable {
    case lobby
    case configuration
    case playing
    case results
}

public struct RoomSnapshot: Codable, Equatable, Sendable {
    public var descriptor: RoomDescriptor
    public var participants: [Participant]
    public var configuration: GameConfiguration
    public var revision: Int

    public init(
        descriptor: RoomDescriptor,
        participants: [Participant],
        configuration: GameConfiguration = .init(),
        revision: Int = 0
    ) {
        self.descriptor = descriptor
        self.participants = participants
        self.configuration = configuration
        self.revision = revision
    }
}

public struct AuthChallenge: Codable, Equatable, Sendable {
    public let salt: Data
    public let nonce: Data

    public init(salt: Data, nonce: Data) {
        self.salt = salt
        self.nonce = nonce
    }
}

public struct JoinRequest: Codable, Equatable, Sendable {
    public let participantID: UUID
    public let nickname: String
    public let authenticationCode: Data
    public let sessionToken: String?
    /// Local, non-synced identifier of the joining device (see `DeviceIdentity`).
    /// Optional so that older clients that omit it remain protocol-v1 compatible;
    /// the host falls back to token-only seat reclaim when it is absent.
    public let deviceInstallID: UUID?

    public init(
        participantID: UUID,
        nickname: String,
        authenticationCode: Data,
        sessionToken: String?,
        deviceInstallID: UUID? = nil
    ) {
        self.participantID = participantID
        self.nickname = nickname
        self.authenticationCode = authenticationCode
        self.sessionToken = sessionToken
        self.deviceInstallID = deviceInstallID
    }
}

public struct JoinResponse: Codable, Equatable, Sendable {
    public let accepted: Bool
    public let reason: String?
    public let sessionToken: String?

    public init(accepted: Bool, reason: String?, sessionToken: String?) {
        self.accepted = accepted
        self.reason = reason
        self.sessionToken = sessionToken
    }
}

public enum NetworkMessage: Codable, Equatable, Sendable {
    case challenge(AuthChallenge)
    case join(JoinRequest)
    case joinResponse(JoinResponse)
    case room(RoomSnapshot)
    case updateConfiguration(GameConfiguration)
    case enterConfiguration
    case startGame
    case action(GameAction)
    case gameState(ClientGameSnapshot)
    case returnToConfiguration
    case leave
    /// Host → clients: the match was paused (`true`) or resumed (`false`) by the host.
    /// Carried as a standalone control signal rather than on the snapshot so it can
    /// ride any transport unchanged and does not perturb game-state versioning.
    case setPaused(Bool)
    /// Host → clients: the host saved the whole match and is stepping away. Clients
    /// keep their local rejoin record and show a "match saved" notice rather than a
    /// hard disconnect error.
    case sessionSuspended
    case error(String)
    case ping
}

public struct WireEnvelope: Codable, Equatable, Sendable {
    public static let currentProtocolVersion = 1

    public let protocolVersion: Int
    public let messageID: UUID
    public let roomID: UUID
    public let senderID: UUID
    public let sequence: UInt64
    public let payload: NetworkMessage

    public init(
        protocolVersion: Int = WireEnvelope.currentProtocolVersion,
        messageID: UUID = UUID(),
        roomID: UUID,
        senderID: UUID,
        sequence: UInt64,
        payload: NetworkMessage
    ) {
        self.protocolVersion = protocolVersion
        self.messageID = messageID
        self.roomID = roomID
        self.senderID = senderID
        self.sequence = sequence
        self.payload = payload
    }
}

public enum ProtocolError: Error, Equatable, Sendable {
    case frameTooLarge
    case incompatibleVersion
    case invalidFrame
}

public struct LengthPrefixedFramer: Sendable {
    public static let maximumFrameSize = 1_048_576
    private var buffer = Data()

    public init() {}

    public static func frame(_ payload: Data) throws -> Data {
        guard payload.count <= maximumFrameSize else { throw ProtocolError.frameTooLarge }
        var length = UInt32(payload.count).bigEndian
        var data = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        data.append(payload)
        return data
    }

    public mutating func append(_ data: Data) throws -> [Data] {
        buffer.append(data)
        var frames: [Data] = []
        while buffer.count >= 4 {
            let length = buffer.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            guard length <= Self.maximumFrameSize else { throw ProtocolError.frameTooLarge }
            let total = 4 + Int(length)
            guard buffer.count >= total else { break }
            frames.append(buffer.subdata(in: 4 ..< total))
            buffer.removeSubrange(0 ..< total)
        }
        return frames
    }
}

public protocol RoomDiscovery: Sendable {
    var rooms: AsyncStream<[RoomDescriptor]> { get }
    func start() async
    func stop() async
}

public enum TransportEvent: Sendable {
    case connected
    case disconnected(Error?)
    case message(WireEnvelope)
}

public protocol SessionTransport: Sendable {
    var events: AsyncStream<TransportEvent> { get }
    func send(_ envelope: WireEnvelope) async throws
    func disconnect() async
}

public protocol BotController: Sendable {
    func chooseAction(from snapshot: ClientGameSnapshot, difficulty: BotDifficulty) async -> GameAction
}
