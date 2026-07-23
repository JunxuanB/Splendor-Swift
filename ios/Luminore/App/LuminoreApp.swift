import SwiftData
import SwiftUI

@main
struct LuminoreApp: App {
    private let modelContainer = PersistenceController.makeContainer()
    @AppStorage("languageOverride") private var languageOverride = "system"

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.locale, selectedLocale)
        }
        .modelContainer(modelContainer)
    }

    private var selectedLocale: Locale {
        switch languageOverride {
        case "zh-Hans": Locale(identifier: "zh-Hans")
        case "en": Locale(identifier: "en")
        default: .autoupdatingCurrent
        }
    }
}
