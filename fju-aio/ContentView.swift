import SwiftUI

// MARK: - Navigation Destinations

enum AppDestination: Hashable {
    case courseSchedule
    case grades
    case leaveRequest
    case attendance
    case semesterCalendar
    case assignments
    case checkIn
    case enrollmentCertificate
    case campusMap
}

// MARK: - Tab Enum

enum AppTab: Hashable {
    case home
    case allFunctions
    case settings
}

// MARK: - Root View

struct ContentView: View {
    @State private var selectedTab: AppTab = .home
    @Environment(SyncStatusManager.self) private var syncStatus

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("首頁", systemImage: "house.fill", value: .home) {
                NavigationStack {
                    HomeView()
                        .navigationDestination(for: AppDestination.self) { destination in
                            destinationView(for: destination)
                        }
                }
            }

            Tab("全部功能", systemImage: "square.grid.2x2.fill", value: .allFunctions) {
                NavigationStack {
                    AllFunctionsView()
                        .navigationDestination(for: AppDestination.self) { destination in
                            destinationView(for: destination)
                        }
                }
            }

            Tab("設定", systemImage: "gearshape.fill", value: .settings) {
                NavigationStack {
                    SettingsView()
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if syncStatus.isSyncing {
                syncBanner
            }
        }
        .animation(.easeInOut(duration: 0.3), value: syncStatus.isSyncing)
    }

    private var syncBanner: some View {
        HStack(spacing: 8) {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.mini)
            Text(syncStatus.message)
                .font(.caption)
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    @ViewBuilder
    private func destinationView(for destination: AppDestination) -> some View {
        switch destination {
        case .courseSchedule:    CourseScheduleView()
        case .grades:           GradesView()
        case .leaveRequest:     LeaveRequestView()
        case .attendance:       AttendanceView()
        case .semesterCalendar: SemesterCalendarView()
        case .assignments:      AssignmentsView()
        case .checkIn:                  CheckInView()
        case .enrollmentCertificate:    EnrollmentCertificateView()
        case .campusMap:                CampusMapView()
        }
    }
}

#Preview {
    ContentView()
        .environment(\.fjuService, FJUService.shared)
        .environment(HomePreferences())
}
