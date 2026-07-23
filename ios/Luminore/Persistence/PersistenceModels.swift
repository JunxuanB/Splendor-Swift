import Foundation
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
    var issuerUUID: UUID = UUID()
    var issuerNicknameSnapshot: String = ""
    var gameID: UUID = UUID()
    var awardedAt: Date = Date()

    init(issuerUUID: UUID, issuerNicknameSnapshot: String, gameID: UUID, awardedAt: Date = Date()) {
        self.issuerUUID = issuerUUID
        self.issuerNicknameSnapshot = issuerNicknameSnapshot
        self.gameID = gameID
        self.awardedAt = awardedAt
    }
}

@Model
final class CompletedGameRecord {
    var id: UUID = UUID()
    var gameID: UUID = UUID()
    var modeRawValue: String = "standard"
    var endedAt: Date = Date()
    var resultPayload: Data = Data()

    init(gameID: UUID, modeRawValue: String, endedAt: Date = Date(), resultPayload: Data = Data()) {
        self.gameID = gameID
        self.modeRawValue = modeRawValue
        self.endedAt = endedAt
        self.resultPayload = resultPayload
    }
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
