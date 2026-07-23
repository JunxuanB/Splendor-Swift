import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// A per-installation identity.
///
/// Splendor's account model stores a single UUID in iCloud, so every device
/// signed into the same Apple ID reads the *same* account UUID. That UUID answers
/// "who is this person"; it cannot answer "which device is this". `DeviceIdentity`
/// fills that gap: `installID` is generated locally on first launch and never
/// synced. It is the second layer of the three-layer identity model
/// (account profile → device install → match participant) and underpins both the
/// LAN reconnect key and the presence lock.
enum DeviceIdentity {
    private static let installIDKey = "deviceInstallID"

    /// Stable identifier for this app installation. Local-only; never written to
    /// iCloud/CloudKit, so two devices sharing one Apple ID hold distinct values.
    static let installID: UUID = {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: installIDKey), let existing = UUID(uuidString: raw) {
            return existing
        }
        let fresh = UUID()
        defaults.set(fresh.uuidString, forKey: installIDKey)
        return fresh
    }()

    /// Human-readable label for this device, used only in soft presence prompts
    /// ("this profile is playing on <name>"). Best-effort: modern iOS returns a
    /// generic model name unless the app is specially entitled. Main-actor isolated
    /// because `UIDevice` is.
    @MainActor
    static var deviceName: String {
        #if canImport(UIKit)
        let name = UIDevice.current.name
        return name.isEmpty ? UIDevice.current.model : name
        #else
        return "This device"
        #endif
    }
}
