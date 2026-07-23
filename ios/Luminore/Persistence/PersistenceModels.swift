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

    static func makeContainer() -> ModelContainer {
        let schema = Schema([AccountProfile.self, MedalRecord.self, CompletedGameRecord.self, PresenceLease.self])
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            // `.none` is essential: ModelConfiguration defaults cloudKitDatabase to
            // `.automatic`, which — because the app carries a CloudKit entitlement —
            // makes even an in-memory (/dev/null) store spin up CloudKit mirroring
            // and crash under tests. Unit tests must stay fully local.
            let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            do {
                return try ModelContainer(for: schema, configurations: [memory])
            } catch {
                fatalError("Unable to create Luminore test store: \(error)")
            }
        }
        let storeURL = URL.applicationSupportDirectory.appending(path: "Luminore.store")
        try? FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        do {
            let cloud = ModelConfiguration(
                "Luminore",
                schema: schema,
                url: storeURL,
                cloudKitDatabase: .private(cloudContainerIdentifier)
            )
            return try ModelContainer(for: schema, configurations: [cloud])
        } catch {
            // The app remains usable when a device has no iCloud account. Data
            // stays local and CloudKit is retried on a later clean launch.
            let local = ModelConfiguration("Luminore", schema: schema, url: storeURL)
            do {
                return try ModelContainer(for: schema, configurations: [local])
            } catch {
                fatalError("Unable to create Luminore data store: \(error)")
            }
        }
    }
}
