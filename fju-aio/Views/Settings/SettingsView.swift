import SwiftUI

struct SettingsView: View {
    @State private var versionTapCount = 0
    @State private var showDebugScreen = false
    
    var body: some View {
        List {
            Section("帳號") {
                HStack {
                    Image(systemName: "person.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.gray)
                    VStack(alignment: .leading) {
                        Text("學生姓名")
                            .font(.headline)
                        Text("410XXXXXX")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("關於") {
                HStack {
                    Text("版本")
                    Spacer()
                    Text("1.0.0")
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    versionTapCount += 1
                    if versionTapCount >= 5 {
                        showDebugScreen = true
                        versionTapCount = 0
                    }
                }
            }
        }
        .navigationTitle("設定")
        .navigationDestination(isPresented: $showDebugScreen) {
            DebugView()
        }
    }
}

struct DebugView: View {
    @Environment(\.fjuService) private var service
    @Environment(AuthenticationManager.self) private var authManager
    @State private var courses: [Course] = []
    @State private var grades: [Grade] = []
    @State private var gpaSummary: GPASummary?
    @State private var quickLinks: [QuickLink] = []
    @State private var leaveRequests: [LeaveRequest] = []
    @State private var attendanceRecords: [AttendanceRecord] = []
    @State private var calendarEvents: [CalendarEvent] = []
    @State private var assignments: [Assignment] = []
    @State private var availableSemesters: [String] = []
    @State private var isLoading = false
    @State private var checkInEnabled = ModuleRegistry.isCheckInFeatureEnabled
    @State private var tronClassSession: TronClassSession?
    @State private var hasStoredCredentials = false
    
    var body: some View {
        List {
            Section("系統資訊") {
                InfoRow(label: "App 版本", value: "1.0.0")
                InfoRow(label: "Build", value: "1")
                InfoRow(label: "iOS 版本", value: UIDevice.current.systemVersion)
                InfoRow(label: "裝置型號", value: UIDevice.current.model)
                InfoRow(label: "裝置名稱", value: UIDevice.current.name)
            }
            
            Section("認證狀態") {
                InfoRow(label: "登入狀態", value: authManager.isAuthenticated ? "已登入" : "未登入")
                if let userId = authManager.currentUserId {
                    InfoRow(label: "用戶 ID", value: "\(userId)")
                }
                InfoRow(label: "儲存的憑證", value: hasStoredCredentials ? "存在" : "不存在")
            }
            
            // TronClass Session
            if let session = tronClassSession {
                Section("TronClass Session") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Session ID")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(session.sessionId)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    
                    InfoRow(label: "用戶 ID", value: "\(session.userId)")
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("過期時間")
                            Spacer()
                            Text(session.expiresAt.formatted(date: .abbreviated, time: .shortened))
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("狀態")
                            Spacer()
                            Text(session.isExpired ? "已過期" : "有效")
                                .foregroundStyle(session.isExpired ? .red : .green)
                        }
                    }
                    
                    if !session.isExpired {
                        let timeRemaining = session.expiresAt.timeIntervalSince(Date())
                        let hours = Int(timeRemaining) / 3600
                        let minutes = (Int(timeRemaining) % 3600) / 60
                        InfoRow(label: "剩餘時間", value: "\(hours)小時 \(minutes)分鐘")
                    }
                }
            }
            
            // Placeholder for future sessions
            Section("其他 API Sessions") {
                Text("校務系統 Session - 尚未實作")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("圖書館系統 Session - 尚未實作")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section("服務狀態") {
                InfoRow(label: "服務類型", value: String(describing: type(of: service)))
                InfoRow(label: "可用學期", value: availableSemesters.joined(separator: ", "))
            }
            
            Section("隱藏功能") {
                Toggle("啟用課程簽到功能", isOn: $checkInEnabled)
                    .onChange(of: checkInEnabled) { _, newValue in
                        if newValue {
                            ModuleRegistry.enableCheckInFeature()
                        } else {
                            ModuleRegistry.disableCheckInFeature()
                        }
                    }
                
                if checkInEnabled {
                    Text("課程簽到功能已啟用，可在「全部功能」中找到")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Section("資料統計") {
                InfoRow(label: "課程數量", value: "\(courses.count)")
                InfoRow(label: "成績數量", value: "\(grades.count)")
                InfoRow(label: "快速連結", value: "\(quickLinks.count)")
                InfoRow(label: "請假記錄", value: "\(leaveRequests.count)")
                InfoRow(label: "出缺席記錄", value: "\(attendanceRecords.count)")
                InfoRow(label: "行事曆事件", value: "\(calendarEvents.count)")
                InfoRow(label: "作業數量", value: "\(assignments.count)")
                if let gpa = gpaSummary {
                    InfoRow(label: "學期 GPA", value: String(format: "%.2f", gpa.semesterGPA))
                    InfoRow(label: "累計 GPA", value: String(format: "%.2f", gpa.cumulativeGPA))
                }
            }
            
            Section("課程詳情") {
                ForEach(courses) { course in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(course.name)
                            .font(.headline)
                        Text("ID: \(course.id) | 教師: \(course.instructor)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("星期\(course.dayOfWeek) 第\(course.startPeriod)-\(course.endPeriod)節 | \(course.location)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Section("成績詳情") {
                ForEach(grades) { grade in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(grade.courseName)
                            .font(.headline)
                        HStack {
                            Text("學分: \(grade.credits)")
                            if let score = grade.score {
                                Text("| 分數: \(Int(score))")
                            }
                            if let letter = grade.letterGrade {
                                Text("| 等第: \(letter)")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            
            Section("作業詳情") {
                ForEach(assignments) { assignment in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(assignment.title)
                                .font(.headline)
                            Spacer()
                            Image(systemName: assignment.isCompleted ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(assignment.isCompleted ? .green : .secondary)
                        }
                        Text(assignment.courseName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
        Text("截止: \(assignment.dueDate.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Section("出缺席統計") {
                let presentCount = attendanceRecords.filter { $0.status == .present }.count
                let absentCount = attendanceRecords.filter { $0.status == .absent }.count
                let lateCount = attendanceRecords.filter { $0.status == .late }.count
                let excusedCount = attendanceRecords.filter { $0.status == .excused }.count
                
                InfoRow(label: "出席", value: "\(presentCount)")
                InfoRow(label: "缺席", value: "\(absentCount)")
                InfoRow(label: "遲到", value: "\(lateCount)")
                InfoRow(label: "請假", value: "\(excusedCount)")
            }
            
            Section("行事曆事件") {
                ForEach(calendarEvents) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.title)
                            .font(.headline)
                        Text(event.category.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let endDate = event.endDate {
                            Text("\(event.startDate.formatted(date: .abbreviated, time: .omitted)) - \(endDate.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(event.startDate.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            
            Section("操作") {
                Button("重新載入所有資料") {
                    Task {
                        await loadAllData()
                    }
                }
                .disabled(isLoading)
                
                Button("重新載入 TronClass Session") {
                    Task {
                        await loadTronClassSession()
                    }
                }
                .disabled(isLoading)
            }
        }
        .navigationTitle("除錯資訊")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadAllData()
            await loadTronClassSession()
            checkCredentials()
        }
        .overlay {
            if isLoading {
                ProgressView("載入中...")
                    .padding()
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    
    private func loadAllData() async {
        isLoading = true
        
        async let coursesTask = service.fetchCourses(semester: "113-2")
        async let gradesTask = service.fetchGrades(semester: "113-2")
        async let gpaTask = service.fetchGPASummary(semester: "113-2")
        async let quickLinksTask = service.fetchQuickLinks()
        async let leaveRequestsTask = service.fetchLeaveRequests()
        async let attendanceTask = service.fetchAttendanceRecords(semester: "113-2")
        async let calendarTask = service.fetchCalendarEvents(semester: "113-2")
        async let assignmentsTask = service.fetchAssignments()
        async let semestersTask = service.fetchAvailableSemesters()
        
        do {
            courses = try await coursesTask
            grades = try await gradesTask
            gpaSummary = try await gpaTask
            quickLinks = try await quickLinksTask
            leaveRequests = try await leaveRequestsTask
            attendanceRecords = try await attendanceTask
            calendarEvents = try await calendarTask
            assignments = try await assignmentsTask
            availableSemesters = try await semestersTask
        } catch {
            print("載入資料時發生錯誤: \(error)")
        }
        
        isLoading = false
    }
    
    private func loadTronClassSession() async {
        do {
            tronClassSession = try await authManager.getValidSession()
        } catch {
            print("無法載入 TronClass Session: \(error)")
            tronClassSession = nil
        }
    }
    
    private func checkCredentials() {
        hasStoredCredentials = CredentialStore.shared.hasLDAPCredentials()
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environment(\.fjuService, MockFJUService())
            .environment(AuthenticationManager())
    }
}

