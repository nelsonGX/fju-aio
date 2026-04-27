import SwiftUI

@main
struct FJUApp: App {
    @State private var authManager = AuthenticationManager()
    private let syncStatus = SyncStatusManager.shared

    init() {
        _ = CourseNotificationManager.shared
    }

    var body: some Scene {
        WindowGroup {
            if authManager.isAuthenticated {
                ContentView()
                    .environment(\.fjuService, FJUService.shared)
                    .environment(HomePreferences())
                    .environment(authManager)
                    .environment(syncStatus)
            } else {
                LoginView()
                    .environment(authManager)
            }
        }
    }
}
