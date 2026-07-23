import Foundation
import LuminoreCore
import SwiftData

/// A host-side, full serialization of an in-progress match so it can be closed and
/// resumed later ("存档游戏"). Lives only on the host device in a **local-only**
/// SwiftData store (see `PersistenceController`): the state blob is large and there
/// is no cross-device resume, so it is intentionally never mirrored to CloudKit.
@Model
final class SavedGameRecord {
    var id: UUID = UUID()
    /// `AccountProfile.uuid.uuidString` of the host. Stored as a string so it can be
    /// used in a `#Predicate` — UUID equality traps inside SwiftData.
    var ownerKey: String = ""
    var gameID: UUID = UUID()
    var roomID: UUID = UUID()
    var roomName: String = ""
    var modeRawValue: String = "standard"
    /// Transport used by this saved match. The default keeps records written by
    /// releases before internet/nearby support compatible as LAN saves.
    var transportRawValue: String = MultiplayerMode.lan.rawValue
    /// Snapshot of the relay base URL. Empty for LAN and Nearby.
    var serverURLString: String = ""
    var isPublic: Bool = true
    /// The local participant's reconnect credential. Host saves also keep the full
    /// per-seat map in `sessionPayload`.
    var sessionToken: String = ""
    var savedAt: Date = Date()
    /// Encoded `GameState`.
    var statePayload: Data = Data()
    /// Encoded reconnect maps (session tokens + seat installs) so returning players
    /// can reclaim their seats after the room is re-hosted.
    var sessionPayload: Data = Data()

    init(
        ownerKey: String,
        gameID: UUID,
        roomID: UUID,
        roomName: String,
        modeRawValue: String,
        transportRawValue: String = MultiplayerMode.lan.rawValue,
        serverURLString: String = "",
        isPublic: Bool = true,
        sessionToken: String = "",
        statePayload: Data,
        sessionPayload: Data,
        savedAt: Date = Date()
    ) {
        self.ownerKey = ownerKey
        self.gameID = gameID
        self.roomID = roomID
        self.roomName = roomName
        self.modeRawValue = modeRawValue
        self.transportRawValue = transportRawValue
        self.serverURLString = serverURLString
        self.isPublic = isPublic
        self.sessionToken = sessionToken
        self.statePayload = statePayload
        self.sessionPayload = sessionPayload
        self.savedAt = savedAt
    }

    var multiplayerMode: MultiplayerMode {
        MultiplayerMode(rawValue: transportRawValue) ?? .lan
    }

    var serverURL: URL? {
        serverURLString.isEmpty ? nil : URL(string: serverURLString)
    }
}

/// A lightweight per-device marker that this profile has an unfinished match. Written
/// by both host and clients when a game starts, refreshed as snapshots arrive, and
/// cleared when the match finishes or the player leaves for good. Drives the home
/// "rejoin in progress" entry and the Live Activity. Local-only, like `SavedGameRecord`.
@Model
final class ActiveMatchRecord {
    /// `AccountProfile.uuid.uuidString` of the owner. String for `#Predicate` safety.
    var ownerKey: String = ""
    var gameID: UUID = UUID()
    var roomID: UUID = UUID()
    var roomName: String = ""
    var modeRawValue: String = "standard"
    var transportRawValue: String = MultiplayerMode.lan.rawValue
    var serverURLString: String = ""
    var isPublic: Bool = true
    var sessionToken: String = ""
    var myParticipantID: UUID = UUID()
    var wasHost: Bool = false
    var updatedAt: Date = Date()
    var lastKnownIsMyTurn: Bool = false
    var lastKnownStatusRaw: String = "playing"

    init(
        ownerKey: String,
        gameID: UUID,
        roomID: UUID,
        roomName: String,
        modeRawValue: String,
        myParticipantID: UUID,
        wasHost: Bool,
        transportRawValue: String = MultiplayerMode.lan.rawValue,
        serverURLString: String = "",
        isPublic: Bool = true,
        sessionToken: String = "",
        updatedAt: Date = Date(),
        lastKnownIsMyTurn: Bool = false,
        lastKnownStatusRaw: String = "playing"
    ) {
        self.ownerKey = ownerKey
        self.gameID = gameID
        self.roomID = roomID
        self.roomName = roomName
        self.modeRawValue = modeRawValue
        self.myParticipantID = myParticipantID
        self.wasHost = wasHost
        self.transportRawValue = transportRawValue
        self.serverURLString = serverURLString
        self.isPublic = isPublic
        self.sessionToken = sessionToken
        self.updatedAt = updatedAt
        self.lastKnownIsMyTurn = lastKnownIsMyTurn
        self.lastKnownStatusRaw = lastKnownStatusRaw
    }

    var multiplayerMode: MultiplayerMode {
        MultiplayerMode(rawValue: transportRawValue) ?? .lan
    }

    var serverURL: URL? {
        serverURLString.isEmpty ? nil : URL(string: serverURLString)
    }
}
