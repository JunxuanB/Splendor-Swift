import Foundation
import LuminoreCore

/// A transport that goes nowhere. Used by local tutorials so a fully
/// host-authoritative game can run entirely on-device without advertising a room
/// or touching the network. Every send is dropped; `host` immediately reports
/// `.ready` for symmetry with the real transports (the tutorial actually bypasses
/// the connecting flow and jumps straight to `.game`, so this is belt-and-braces).
@MainActor
final class LoopbackTransport: MatchTransport {
    var mode: MultiplayerMode { .lan }
    var roomCode: String? { nil }
    var onEvent: ((MatchTransportEvent) -> Void)?
    var onRoomsChanged: (([DiscoveredMatchRoom]) -> Void)?

    func startBrowsing() {}
    func stopBrowsing() {}

    func resolveRoom(code: String) async throws -> DiscoveredMatchRoom {
        throw MatchTransportError.roomNotFound
    }

    func resolveRoom(id: UUID) async throws -> DiscoveredMatchRoom {
        throw MatchTransportError.roomNotFound
    }

    func host(room: RoomDescriptor, isPublic: Bool) {
        onEvent?(.ready)
    }

    func join(room: DiscoveredMatchRoom) {}
    func reconnect() {}
    func send(_ envelope: WireEnvelope, to recipient: TransportRecipient) {}
    func updateRoom(_ descriptor: RoomDescriptor, isPublic: Bool) {}
    func disconnect(closeRoom: Bool) {}
}
