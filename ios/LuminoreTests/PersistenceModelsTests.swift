import SwiftData
import XCTest
@testable import Luminore

@MainActor
final class PersistenceModelsTests: XCTestCase {
    // A single shared in-memory container for the whole test class. iOS 26's
    // SwiftData traps when several ModelContainers for the same schema are alive at
    // once in one process (here the test host app already owns one), so we create
    // exactly one and give each test an isolated child context inside it.
    private static let sharedContainer: ModelContainer = {
        let schema = Schema([AccountProfile.self, MedalRecord.self, CompletedGameRecord.self, PresenceLease.self])
        // cloudKitDatabase: .none keeps the in-memory store from attaching CloudKit
        // mirroring (which the app's entitlement would otherwise trigger and crash).
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        // swiftlint:disable:next force_try
        return try! ModelContainer(for: schema, configurations: [configuration])
    }()

    private func makeContext() throws -> ModelContext {
        let context = ModelContext(Self.sharedContainer)
        // Shared container ⇒ wipe prior tests' rows so each test starts empty.
        try context.delete(model: AccountProfile.self)
        try context.delete(model: MedalRecord.self)
        try context.delete(model: CompletedGameRecord.self)
        try context.delete(model: PresenceLease.self)
        try context.save()
        return context
    }

    func testAccountAndPlaceholderRecordsPersistInMemory() throws {
        let context = try makeContext()

        let account = AccountProfile(nickname: "Aurora")
        let gameID = UUID()
        context.insert(account)
        context.insert(MedalRecord(issuerUUID: UUID(), issuerNicknameSnapshot: "Nova", gameID: gameID))
        context.insert(CompletedGameRecord(gameID: gameID, modeRawValue: "standard"))
        try context.save()

        let accounts = try context.fetch(FetchDescriptor<AccountProfile>())
        let medals = try context.fetch(FetchDescriptor<MedalRecord>())
        let games = try context.fetch(FetchDescriptor<CompletedGameRecord>())
        XCTAssertEqual(accounts.map(\.nickname), ["Aurora"])
        XCTAssertEqual(medals.first?.gameID, gameID)
        XCTAssertEqual(games.first?.gameID, gameID)
        // logicalKey is now unique per profile rather than a shared "primary" key.
        XCTAssertEqual(account.logicalKey, account.uuid.uuidString)
    }

    func testMultipleProfilesCoexistUnderOneStore() throws {
        let context = try makeContext()
        let first = AccountProfile(nickname: "Kid A")
        let second = AccountProfile(nickname: "Kid B")
        context.insert(first)
        context.insert(second)
        try context.save()

        let profiles = try context.fetch(FetchDescriptor<AccountProfile>(sortBy: [SortDescriptor(\.createdAt)]))
        XCTAssertEqual(profiles.count, 2)
        XCTAssertNotEqual(first.uuid, second.uuid)
        XCTAssertNotEqual(first.logicalKey, second.logicalKey)
    }

    func testPresenceLeaseStoresDeviceScopedIdentity() throws {
        let context = try makeContext()
        let profileUUID = UUID()
        let install = UUID()
        context.insert(PresenceLease(
            profileUUID: profileUUID,
            deviceInstallID: install,
            deviceName: "iPhone",
            activityLabel: "lan"
        ))
        try context.save()

        // Filter in Swift: UUID-equality #Predicate traps inside SwiftData on
        // current OS versions (mirrors PresenceCoordinator.leases(for:)).
        let leases = try context.fetch(FetchDescriptor<PresenceLease>())
            .filter { $0.profileUUID == profileUUID }
        XCTAssertEqual(leases.count, 1)
        XCTAssertEqual(leases.first?.deviceInstallID, install)
    }
}
