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
