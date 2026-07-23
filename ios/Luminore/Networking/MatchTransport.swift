import Foundation
import LuminoreCore

struct TransportPeerID: Hashable, Sendable {
    let rawValue: String

    init(_ rawValue: String = UUID().uuidString) {
        self.rawValue = rawValue
    }
}

enum TransportRecipient: Sendable {
    case host
    case peer(TransportPeerID)
    case allClients
}

struct DiscoveredMatchRoom: Identifiable, Hashable, Sendable {
    let descriptor: RoomDescriptor
    var id: UUID { descriptor.id }
}

enum MatchTransportEvent: Sendable {
    case ready
    case peerConnected(TransportPeerID)
    case peerDisconnected(TransportPeerID, String?)
    case message(WireEnvelope, from: TransportPeerID)
    case hostUnavailable
    case hostAvailable
    /// The relay permanently removed the room. Unlike a transient host outage this
    /// is terminal and must never start another reconnect attempt.
    case roomClosed(String)
    case failed(String)
}

@MainActor
protocol MatchTransport: AnyObject {
    var mode: MultiplayerMode { get }
    var roomCode: String? { get }
    var onEvent: ((MatchTransportEvent) -> Void)? { get set }
    var onRoomsChanged: (([DiscoveredMatchRoom]) -> Void)? { get set }

    func startBrowsing()
    func stopBrowsing()
    func resolveRoom(code: String) async throws -> DiscoveredMatchRoom
    func resolveRoom(id: UUID) async throws -> DiscoveredMatchRoom
    func host(room: RoomDescriptor, isPublic: Bool)
    func join(room: DiscoveredMatchRoom)
    func reconnect()
    func send(_ envelope: WireEnvelope, to recipient: TransportRecipient)
    func updateRoom(_ descriptor: RoomDescriptor, isPublic: Bool)
    func disconnect(closeRoom: Bool)
}

enum MatchTransportFactory {
    @MainActor
    static func make(mode: MultiplayerMode, serverURL: URL? = nil) -> any MatchTransport {
        switch mode {
        case .lan:
            LANTransport()
        case .internet:
            InternetTransport(serverURL: serverURL ?? InternetServerSettings.defaultURL)
        case .nearby:
            MultipeerTransport()
        }
    }
}

enum MatchTransportError: LocalizedError {
    case unsupportedRoomCode
    case roomNotFound
    case invalidServer
    case incompatibleServer
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .unsupportedRoomCode: NSLocalizedString("room_code_unsupported", comment: "")
        case .roomNotFound: NSLocalizedString("room_not_found", comment: "")
        case .invalidServer: NSLocalizedString("invalid_server_url", comment: "")
        case .incompatibleServer: NSLocalizedString("incompatible_server", comment: "")
        case .invalidResponse: NSLocalizedString("invalid_server_response", comment: "")
        }
    }
}
