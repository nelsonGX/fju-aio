import SwiftUI

struct fju_aioApp: App {
    @State private var homePreferences = HomePreferences()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.fjuService, MockFJUService())
                .environment(homePreferences)
        }
    }
}
