import Foundation

enum DeveloperTools {
    static let unlockTapCount = 5

    static var isEnabledForCurrentBuild: Bool {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String == "1"
    }
}
