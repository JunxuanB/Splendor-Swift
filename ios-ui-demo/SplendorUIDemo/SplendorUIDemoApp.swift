import SwiftUI

@main
struct SplendorUIDemoApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                GameBoardView()
            }
        }
    }
}
