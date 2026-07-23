import Foundation
import SwiftData

/// A CloudKit-synced marker that an account profile is currently active in a match
/// on one specific device installation.
///
/// Each device signed into the same iCloud account writes its own lease, keyed by
/// `deviceInstallID`. A *fresh* lease for the same `profileUUID` from a *different*
/// install means "this profile is already playing somewhere else" — the signal
/// behind the soft presence lock. It is deliberately best-effort: CloudKit sync
/// latency makes it advisory rather than strongly consistent, and stale leases are
/// simply ignored past `PresenceCoordinator.staleInterval`, matching the game's
/// no-anti-cheat stance.
@Model
final class PresenceLease {
    var profileUUID: UUID = UUID()
    var deviceInstallID: UUID = UUID()
    var deviceName: String = ""
    // NB: avoid the property name `context` here — it collides with CoreData/KVC
    // reserved keys and makes SwiftData trap on insert.
    var activityLabel: String = ""
    var startedAt: Date = Date()
    var heartbeatAt: Date = Date()

    init(
        profileUUID: UUID,
        deviceInstallID: UUID,
        deviceName: String,
        activityLabel: String,
        startedAt: Date = Date()
    ) {
        self.profileUUID = profileUUID
        self.deviceInstallID = deviceInstallID
        self.deviceName = deviceName
        self.activityLabel = activityLabel
        self.startedAt = startedAt
        self.heartbeatAt = startedAt
    }
}
