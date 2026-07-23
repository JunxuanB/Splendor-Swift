import Foundation
import LuminoreCore
import SwiftData

@Model
final class AccountProfile {
    // Historically a fixed "primary" dedup key that collapsed every device onto one
    // profile. It is now a per-profile unique value: several profiles can coexist
    // under one iCloud account so that people sharing an Apple ID (e.g. a family)
    // each get their own identity, medals, and history.
    var logicalKey: String = "primary"
    var uuid: UUID = UUID()
    var nickname: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(uuid: UUID = UUID(), nickname: String, createdAt: Date = Date()) {
        self.uuid = uuid
        self.logicalKey = uuid.uuidString
        self.nickname = nickname
        self.createdAt = createdAt
        updatedAt = createdAt
    }
}

@Model
final class MedalRecord {
    var id: UUID = UUID()
    /// Owning `AccountProfile.uuid.uuidString`. Empty values are legacy/unscoped
    /// records and are intentionally hidden from every profile.
    var ownerKey: String = ""
    /// Stable per-profile award identity. CloudKit-backed SwiftData models cannot
    /// use unique constraints, so callers and views deduplicate with this key.
    var logicalKey: String = ""
    var issuerUUID: UUID = UUID()
    var issuerNicknameSnapshot: String = ""
    var gameID: UUID = UUID()
    var awardedAt: Date = Date()

    init(
        ownerKey: String = "",
        issuerUUID: UUID,
        issuerNicknameSnapshot: String,
        gameID: UUID,
        awardedAt: Date = Date()
    ) {
        self.ownerKey = ownerKey
        logicalKey = Self.makeLogicalKey(ownerKey: ownerKey, gameID: gameID, issuerUUID: issuerUUID)
        self.issuerUUID = issuerUUID
        self.issuerNicknameSnapshot = issuerNicknameSnapshot
        self.gameID = gameID
        self.awardedAt = awardedAt
    }

    static func makeLogicalKey(ownerKey: String, gameID: UUID, issuerUUID: UUID) -> String {
        "\(ownerKey)|\(gameID.uuidString)|\(issuerUUID.uuidString)"
    }
}

@Model
final class CompletedGameRecord {
    var id: UUID = UUID()
    var ownerKey: String = ""
    var logicalKey: String = ""
    var gameID: UUID = UUID()
    var localParticipantID: UUID = UUID()
    var modeRawValue: String = "standard"
    var transportRawValue: String = MultiplayerMode.lan.rawValue
    var endedAt: Date = Date()
    var resultPayload: Data = Data()

    init(
        ownerKey: String = "",
        gameID: UUID,
        localParticipantID: UUID = UUID(),
        modeRawValue: String,
        transportRawValue: String = MultiplayerMode.lan.rawValue,
        endedAt: Date = Date(),
        resultPayload: Data = Data()
    ) {
        self.ownerKey = ownerKey
        logicalKey = Self.makeLogicalKey(ownerKey: ownerKey, gameID: gameID)
        self.gameID = gameID
        self.localParticipantID = localParticipantID
        self.modeRawValue = modeRawValue
        self.transportRawValue = transportRawValue
        self.endedAt = endedAt
        self.resultPayload = resultPayload
    }

    static func makeLogicalKey(ownerKey: String, gameID: UUID) -> String {
        "\(ownerKey)|\(gameID.uuidString)"
    }

    var gameMode: GameMode { GameMode(rawValue: modeRawValue) ?? .standard }
    var multiplayerMode: MultiplayerMode { MultiplayerMode(rawValue: transportRawValue) ?? .lan }
    var result: GameResult? { try? JSONDecoder().decode(GameResult.self, from: resultPayload) }
}

enum PersistenceController {
    static let cloudContainerIdentifier = "iCloud.com.junxuanb.Luminore"

    // CloudKit-mirrored models: account identity, medals, history, presence.
    private static let cloudSchema = Schema([
        AccountProfile.self, MedalRecord.self, CompletedGameRecord.self, PresenceLease.self
    ])
    // Local-only models: in-progress/saved matches. Large state blobs and no
    // cross-device resume, so these deliberately never mirror to CloudKit.
    private static let localSchema = Schema([SavedGameRecord.self, ActiveMatchRecord.self])
    private static let fullSchema = Schema([
        AccountProfile.self, MedalRecord.self, CompletedGameRecord.self, PresenceLease.self,
        SavedGameRecord.self, ActiveMatchRecord.self
    ])

    static func makeContainer() -> ModelContainer {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            // `.none` is essential: ModelConfiguration defaults cloudKitDatabase to
            // `.automatic`, which — because the app carries a CloudKit entitlement —
            // makes even an in-memory (/dev/null) store spin up CloudKit mirroring
            // and crash under tests. Unit tests must stay fully local.
            let memory = ModelConfiguration(schema: fullSchema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            do {
                return try ModelContainer(for: fullSchema, configurations: [memory])
            } catch {
                fatalError("Unable to create Luminore test store: \(error)")
            }
        }
        let storeURL = URL.applicationSupportDirectory.appending(path: "Luminore.store")
        let localStoreURL = URL.applicationSupportDirectory.appending(path: "LuminoreLocal.store")
        try? FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // The saved/active-match store is always a plain local store, paired with
        // whichever primary store (cloud or local fallback) we can bring up.
        let resume = ModelConfiguration(
            "LuminoreLocal",
            schema: localSchema,
            url: localStoreURL,
            cloudKitDatabase: .none
        )
        do {
            let cloud = ModelConfiguration(
                "Luminore",
                schema: cloudSchema,
                url: storeURL,
                cloudKitDatabase: .private(cloudContainerIdentifier)
            )
            return try ModelContainer(for: fullSchema, configurations: [cloud, resume])
        } catch {
            // The app remains usable when a device has no iCloud account. Data
            // stays local and CloudKit is retried on a later clean launch.
            let local = ModelConfiguration("Luminore", schema: cloudSchema, url: storeURL)
            do {
                return try ModelContainer(for: fullSchema, configurations: [local, resume])
            } catch {
                fatalError("Unable to create Luminore data store: \(error)")
            }
        }
    }
}
