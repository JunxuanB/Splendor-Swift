import Foundation
import SwiftData

/// Drives the soft presence lock around a match.
///
/// On `claim` the coordinator writes this device's `PresenceLease` for the active
/// profile and reports whether another device already holds a fresh lease for the
/// same profile (a `Conflict`). While the match runs it heartbeats its lease and
/// watches for a newer lease from another install — if one appears, this device has
/// been "taken over" and should leave. `release` removes the lease on exit.
///
/// Everything here is best-effort by design: CloudKit propagation is not instant,
/// so this smooths the common "I opened the same game on my phone and iPad" case
/// rather than enforcing hard mutual exclusion.
@MainActor
final class PresenceCoordinator: ObservableObject {
    struct Conflict: Identifiable, Equatable {
        let id = UUID()
        let deviceName: String
    }

    /// Leases older than this are treated as abandoned (device crashed, lost power).
    static let staleInterval: TimeInterval = 60
    /// How often the active device refreshes its lease and checks for takeover.
    static let heartbeatInterval: TimeInterval = 20

    /// Set to `true` when a newer lease from another device supersedes ours. Views
    /// observe this to leave the match and inform the player.
    @Published var wasTakenOver = false

    private let installID = DeviceIdentity.installID
    private var modelContext: ModelContext?
    private var profileUUID: UUID?
    private var context = ""
    private var startedAt = Date()
    private var heartbeatTask: Task<Void, Never>?

    func configure(_ context: ModelContext) {
        if modelContext == nil { modelContext = context }
    }

    /// Registers this device's lease for `profileUUID` and returns a conflict when
    /// another device already holds a fresh lease for the same profile. Claiming
    /// always makes *this* device the newest lease, so confirming a takeover needs
    /// no further write — the other device notices on its next heartbeat.
    @discardableResult
    func claim(profileUUID: UUID, context: String) -> Conflict? {
        guard modelContext != nil else { return nil }
        self.profileUUID = profileUUID
        self.context = context
        startedAt = Date()
        wasTakenOver = false

        let conflict = liveForeignLease(for: profileUUID).map { Conflict(deviceName: $0.deviceName) }
        upsertOwnLease()
        startHeartbeat()
        return conflict
    }

    func release() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        guard let modelContext, let profileUUID else { return }
        for lease in leases(for: profileUUID) where lease.deviceInstallID == installID {
            modelContext.delete(lease)
        }
        try? modelContext.save()
        self.profileUUID = nil
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.heartbeatInterval))
                guard !Task.isCancelled else { return }
                self?.tick()
            }
        }
    }

    private func tick() {
        guard let profileUUID else { return }
        if let foreign = liveForeignLease(for: profileUUID), foreign.startedAt > startedAt {
            wasTakenOver = true
            release()
            return
        }
        upsertOwnLease()
    }

    // MARK: - Store access

    private func leases(for profileUUID: UUID) -> [PresenceLease] {
        guard let modelContext else { return [] }
        // Fetch all and filter in Swift rather than using a #Predicate on the UUID:
        // UUID-equality predicates trap inside SwiftData on current OS versions. The
        // presence table holds only a few rows (one per active device), so a full
        // fetch is cheap and avoids that crash.
        let all = (try? modelContext.fetch(FetchDescriptor<PresenceLease>())) ?? []
        return all.filter { $0.profileUUID == profileUUID }
    }

    private func liveForeignLease(for profileUUID: UUID) -> PresenceLease? {
        let cutoff = Date().addingTimeInterval(-Self.staleInterval)
        return leases(for: profileUUID)
            .filter { $0.deviceInstallID != installID && $0.heartbeatAt > cutoff }
            .max { $0.startedAt < $1.startedAt }
    }

    private func upsertOwnLease() {
        guard let modelContext, let profileUUID else { return }
        if let own = leases(for: profileUUID).first(where: { $0.deviceInstallID == installID }) {
            own.startedAt = startedAt
            own.heartbeatAt = Date()
            own.activityLabel = context
            own.deviceName = DeviceIdentity.deviceName
        } else {
            modelContext.insert(PresenceLease(
                profileUUID: profileUUID,
                deviceInstallID: installID,
                deviceName: DeviceIdentity.deviceName,
                activityLabel: context,
                startedAt: startedAt
            ))
        }
        try? modelContext.save()
    }
}
