import SwiftUI
import ActivityKit

struct SettingsView: View {
    @Environment(AuthenticationManager.self) private var authManager
    @State private var versionTapCount = 0
    @State private var showDebugScreen = false
    @State private var showLogoutAlert = false
    @State private var sisSession: SISSession?
    @State private var isLoadingSession = false
    private let notificationManager = CourseNotificationManager.shared
    private let syncStatus = SyncStatusManager.shared
    @AppStorage("preferredMapsApp") private var preferredMapsApp = "apple"
    
    var body: some View {
        List {
            Section("帳號") {
                HStack {
                    Image(systemName: "person.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.gray)
                    VStack(alignment: .leading) {
                        Text(sisSession?.userName ?? "學生姓名")
                            .font(.headline)
                        Text(sisSession?.empNo ?? "410XXXXXX")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    if isLoadingSession {
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                
                Button(role: .destructive) {
                    showLogoutAlert = true
                } label: {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("登出")
                    }
                }
            }

            Section("課程通知") {
                Toggle("啟用課程提醒", isOn: Binding(
                    get: { notificationManager.isEnabled },
                    set: { notificationManager.isEnabled = $0 }
                ))

                if notificationManager.isEnabled {
                    Toggle("上課前顯示靈動島", isOn: Binding(
                        get: { notificationManager.notifyBefore },
                        set: { notificationManager.notifyBefore = $0 }
                    ))

                    if notificationManager.notifyBefore {
                        Picker("提前時間", selection: Binding(
                            get: { notificationManager.minutesBefore },
                            set: { notificationManager.minutesBefore = $0 }
                        )) {
                            Text("5 分鐘").tag(5)
                            Text("10 分鐘").tag(10)
                            Text("15 分鐘").tag(15)
                            Text("30 分鐘").tag(30)
                        }
                    }

                    Toggle("上課中顯示靈動島", isOn: Binding(
                        get: { notificationManager.notifyStart },
                        set: { notificationManager.notifyStart = $0 }
                    ))

                    Toggle("下課後顯示靈動島", isOn: Binding(
                        get: { notificationManager.notifyEnd },
                        set: { notificationManager.notifyEnd = $0 }
                    ))
                }
            }
            Section("一般") {
                Toggle("顯示同步狀態列", isOn: Binding(
                    get: { syncStatus.isEnabled },
                    set: { syncStatus.isEnabled = $0 }
                ))
            }

            Section("導航") {
                Picker("預設導航應用程式", selection: $preferredMapsApp) {
                    Text("Apple 地圖").tag("apple")
                    Text("Google 地圖").tag("google")
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
        .alert("確認登出", isPresented: $showLogoutAlert) {
            Button("取消", role: .cancel) {}
            Button("登出", role: .destructive) {
                Task {
                    await performLogout()
                }
            }
        } message: {
            Text("登出後將清除所有已儲存的帳號密碼和 Session 資訊")
        }
        .task {
            await loadSISSession()
        }
        .refreshable {
            await loadSISSession()
        }
    }
    
    private func loadSISSession() async {
        isLoadingSession = true
        do {
            sisSession = try await authManager.getValidSISSession()
        } catch {
            print("無法載入 SIS Session: \(error)")
            sisSession = nil
        }
        isLoadingSession = false
    }
    
    private func performLogout() async {
        do {
            try await authManager.logout()
        } catch {
            print("登出失敗: \(error)")
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
    @State private var leaveRecordCount: Int = 0
    @State private var attendanceRecords: [AttendanceRecord] = []
    @State private var calendarEvents: [CalendarEvent] = []
    @State private var assignments: [Assignment] = []
    @State private var availableSemesters: [String] = []
    @State private var isLoading = false
    @AppStorage(ModuleRegistry.checkInFeatureEnabledKey) private var checkInEnabled = false
    @State private var tronClassSession: TronClassSession?
    @State private var sisSession: SISSession?
    @State private var estuSession: EstuSession?
    @State private var hasStoredCredentials = false
    @State private var sessionLoadError: String?
    @State private var notificationLog: [String] = []
    
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
                
                if let error = sessionLoadError {
                    Text("Session 載入錯誤: \(error)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
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
            } else {
                Section("TronClass Session") {
                    Text("無 Session 資料")
                        .foregroundStyle(.secondary)
                }
            }
            
            // SIS Session
            if let session = sisSession {
                Section("SIS (校務系統) Session") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("JWT Token (完整)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ScrollView(.horizontal, showsIndicators: true) {
                            Text(session.token)
                                .font(.system(.caption2, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(.vertical, 4)
                        }
                        .frame(height: 80)
                    }
                    
                    InfoRow(label: "用戶 ID", value: "\(session.userId)")
                    InfoRow(label: "用戶名稱", value: session.userName)
                    InfoRow(label: "學號", value: session.empNo)
                    
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
                    
                    if let payload = decodeJWTPayload(session.token) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("JWT Payload (解碼)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ScrollView(.horizontal, showsIndicators: true) {
                                Text(payload)
                                    .font(.system(.caption2, design: .monospaced))
                                    .textSelection(.enabled)
                                    .padding(.vertical, 4)
                            }
                            .frame(height: 120)
                        }
                    }
                }
            } else {
                Section("SIS (校務系統) Session") {
                    Text("無 Session 資料")
                        .foregroundStyle(.secondary)
                    Text("提示: 需要先登入才會有 SIS Session")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            
            // ESTU Session
            if let session = estuSession {
                Section("ESTU (選課系統) Session") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ASP.NET Session ID")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(session.sessionId)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ViewState (前 100 字元)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ScrollView(.horizontal, showsIndicators: true) {
                            Text(String(session.viewState.prefix(100)) + "...")
                                .font(.system(.caption2, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(.vertical, 4)
                        }
                        .frame(height: 60)
                    }
                    
                    InfoRow(label: "ViewStateGenerator", value: session.viewStateGenerator)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("EventValidation (前 100 字元)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ScrollView(.horizontal, showsIndicators: true) {
                            Text(String(session.eventValidation.prefix(100)) + "...")
                                .font(.system(.caption2, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(.vertical, 4)
                        }
                        .frame(height: 60)
                    }
                    
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
                        let minutes = Int(timeRemaining) / 60
                        InfoRow(label: "剩餘時間", value: "\(minutes)分鐘")
                    }
                }
            } else {
                Section("ESTU (選課系統) Session") {
                    Text("無 Session 資料")
                        .foregroundStyle(.secondary)
                    Text("提示: 需要先登入並訪問課表才會有 ESTU Session")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            
            Section("服務狀態") {
                InfoRow(label: "服務類型", value: String(describing: type(of: service)))
                InfoRow(label: "可用學期", value: availableSemesters.joined(separator: ", "))
            }
            
            Section("隱藏功能") {
                Toggle("啟用課程簽到功能", isOn: $checkInEnabled)

                if checkInEnabled {
                    Text("課程簽到功能已啟用，可在「全部功能」中找到")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                NavigationLink("測試簽到 UI") {
                    CheckInTestView()
                }
            }
            
            Section("資料統計") {
                InfoRow(label: "課程數量", value: "\(courses.count)")
                InfoRow(label: "成績數量", value: "\(grades.count)")
                InfoRow(label: "快速連結", value: "\(quickLinks.count)")
                InfoRow(label: "請假記錄", value: "\(leaveRecordCount)")
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
            
            Section("Live Activity 測試（即時）") {
                let nm = CourseNotificationManager.shared

                Button("Live Activity — 上課前") {
                    log("▶ 測試 Live Activity (before)...")
                    Task {
                        let sample = courses.first ?? sampleCourse()
                        let registered = await nm.fireTestLiveActivity(course: sample, phase: .before)
                        log(registered ? "✅ Live Activity 已啟動並向伺服器註冊 (before)" : "❌ Live Activity 伺服器註冊失敗 (before)")
                    }
                }

                Button("Live Activity — 上課中") {
                    log("▶ 測試 Live Activity (during)...")
                    Task {
                        let sample = courses.first ?? sampleCourse()
                        let registered = await nm.fireTestLiveActivity(course: sample, phase: .during)
                        log(registered ? "✅ Live Activity 已啟動並向伺服器註冊 (during)" : "❌ Live Activity 伺服器註冊失敗 (during)")
                    }
                }

                Button("Live Activity — 已結束") {
                    log("▶ 測試 Live Activity (ended)...")
                    Task {
                        let sample = courses.first ?? sampleCourse()
                        let registered = await nm.fireTestLiveActivity(course: sample, phase: .ended)
                        log(registered ? "✅ Live Activity 已啟動並向伺服器註冊 (ended)" : "❌ Live Activity 伺服器註冊失敗 (ended)")
                    }
                }

                Button("結束全部 Live Activities") {
                    log("▶ 結束全部 Live Activities...")
                    Task {
                        await nm.endAllLiveActivities()
                        log("✅ 全部結束")
                    }
                }
                .foregroundStyle(.red)
            }

            Section("Live Activity 伺服器測試") {
                let nm = CourseNotificationManager.shared

                Text("啟動後可關閉 App，等待伺服器在指定時間推送狀態更新")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("排程 1 分鐘後上課（伺服器推送）") {
                    log("▶ 排程 1 分鐘後的 Live Activity...")
                    Task {
                        let sample = courses.first ?? sampleCourse()
                        let registered = await nm.scheduleDelayedTestLiveActivity(course: sample, delaySeconds: 60)
                        log(registered ? "✅ 已啟動並向伺服器註冊，1 分鐘後伺服器將推送「上課中」" : "❌ Live Activity 伺服器註冊失敗，請查看 Xcode console")
                    }
                }

                Button("排程 3 分鐘後上課（伺服器推送）") {
                    log("▶ 排程 3 分鐘後的 Live Activity...")
                    Task {
                        let sample = courses.first ?? sampleCourse()
                        let registered = await nm.scheduleDelayedTestLiveActivity(course: sample, delaySeconds: 180)
                        log(registered ? "✅ 已啟動並向伺服器註冊，3 分鐘後伺服器將推送「上課中」" : "❌ Live Activity 伺服器註冊失敗，請查看 Xcode console")
                    }
                }

                Button("遠端完整週期測試（30 秒 x 4）") {
                    log("▶ 要求伺服器啟動遠端完整週期 Live Activity 測試...")
                    Task {
                        let sample = courses.first ?? sampleCourse()
                        let scheduled = await nm.requestRemoteFullCycleTest(course: sample)
                        log(scheduled ? "✅ 伺服器已排程：30 秒無顯示、30 秒上課前、30 秒上課中、30 秒結束後消失" : "❌ 遠端完整週期排程失敗，請確認 push-to-start token 已註冊")
                    }
                }

                Button("Ping 伺服器") {
                    log("▶ Ping 伺服器...")
                    Task {
                        let (status, body) = await pingServer()
                        if let status {
                            log(status == 200 ? "✅ 伺服器正常 (HTTP \(status))" : "❌ 伺服器錯誤 (HTTP \(status))\n\(body ?? "")")
                        } else {
                            log("❌ 無法連線至伺服器")
                        }
                    }
                }

                if !notificationLog.isEmpty {
                    Button("清除紀錄", role: .destructive) {
                        notificationLog.removeAll()
                    }
                    .font(.caption)
                }
            }

            if !notificationLog.isEmpty {
                Section("通知紀錄") {
                    ForEach(notificationLog.indices, id: \.self) { i in
                        Text(notificationLog[i])
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(notificationLog[i].hasPrefix("✅") ? .green :
                                             notificationLog[i].hasPrefix("❌") ? .red : .primary)
                            .listRowBackground(Color(.systemGroupedBackground))
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
                
                Button("重新載入所有 Sessions") {
                    Task {
                        await loadAllSessions()
                    }
                }
                .disabled(isLoading)
                
                Button("創建測試 SIS Session") {
                    createMockSISSession()
                }
                
                Button("清除所有 Sessions") {
                    tronClassSession = nil
                    sisSession = nil
                    estuSession = nil
                    sessionLoadError = nil
                }
            }
        }
        .navigationTitle("除錯資訊")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadAllData()
            await loadAllSessions()
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
    
    private func decodeJWTPayload(_ token: String) -> String? {
        let segments = token.components(separatedBy: ".")
        guard segments.count == 3 else { return nil }
        
        var base64 = segments[1]
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data),
              let jsonData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return nil
        }
        
        return jsonString
    }
    
    private func loadAllData() async {
        isLoading = true
        
        async let coursesTask = service.fetchCourses(semester: "113-2")
        async let gradesTask = service.fetchGrades(semester: "113-2")
        async let gpaTask = service.fetchGPASummary(semester: "113-2")
        async let quickLinksTask = service.fetchQuickLinks()
        async let leaveRequestsTask = LeaveService.shared.fetchLeaveRecords(academicYear: 114, semester: 2)
        async let attendanceTask = service.fetchAttendanceRecords(semester: "113-2")
        async let calendarTask = service.fetchCalendarEvents(semester: "113-2")
        async let assignmentsTask = service.fetchAssignments()
        async let semestersTask = service.fetchAvailableSemesters()
        
        do {
            courses = try await coursesTask
            grades = try await gradesTask
            gpaSummary = try await gpaTask
            quickLinks = try await quickLinksTask
            leaveRecordCount = try await leaveRequestsTask.count
            attendanceRecords = try await attendanceTask
            calendarEvents = try await calendarTask
            assignments = try await assignmentsTask
            availableSemesters = try await semestersTask
        } catch {
            print("載入資料時發生錯誤: \(error)")
        }
        
        isLoading = false
    }
    
    private func loadAllSessions() async {
        sessionLoadError = nil
        await loadTronClassSession()
        await loadSISSession()
        await loadEstuSession()
    }
    
    private func loadTronClassSession() async {
        do {
            print("🔍 Loading TronClass session...")
            tronClassSession = try await authManager.getValidSession()
            print("✅ TronClass session loaded")
        } catch {
            print("❌ 無法載入 TronClass Session: \(error)")
            sessionLoadError = "TronClass: \(error.localizedDescription)"
            tronClassSession = nil
        }
    }
    
    private func loadSISSession() async {
        do {
            print("🔍 Loading SIS session...")
            sisSession = try await authManager.getValidSISSession()
            print("✅ SIS session loaded: \(sisSession?.userName ?? "nil")")
        } catch {
            print("❌ 無法載入 SIS Session: \(error)")
            if sessionLoadError == nil {
                sessionLoadError = "SIS: \(error.localizedDescription)"
            } else {
                sessionLoadError? += " | SIS: \(error.localizedDescription)"
            }
            sisSession = nil
        }
    }
    
    private func loadEstuSession() async {
        do {
            print("🔍 Loading ESTU session...")
            estuSession = try await EstuAuthService.shared.getValidSession()
            print("✅ ESTU session loaded")
        } catch {
            print("❌ 無法載入 ESTU Session: \(error)")
            if sessionLoadError == nil {
                sessionLoadError = "ESTU: \(error.localizedDescription)"
            } else {
                sessionLoadError? += " | ESTU: \(error.localizedDescription)"
            }
            estuSession = nil
        }
    }
    
    private func createMockSISSession() {
        sisSession = SISSession(
            token: "xxxx.xxxxx.xxxx",
            userId: 111111111,
            userName: "測試學生",
            empNo: "111111111",
            expiresAt: Date().addingTimeInterval(20 * 60)
        )
        sessionLoadError = nil
        print("✅ 已創建測試 SIS Session")
    }
    
    private func checkCredentials() {
        hasStoredCredentials = CredentialStore.shared.hasLDAPCredentials()
    }

    private func log(_ message: String) {
        let time = Date().formatted(.dateTime.hour().minute().second())
        notificationLog.insert("[\(time)] \(message)", at: 0)
    }

    private func pingServer() async -> (Int?, String?) {
        guard let url = URL(string: "https://fju-aio-notify.appppple.com/activities") else { return (nil, nil) }
        // Use a session that does NOT follow redirects so we see the real status code
        let config = URLSessionConfiguration.ephemeral
        let session = URLSession(configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil)
        do {
            let (data, response) = try await session.data(from: url)
            let http = response as? HTTPURLResponse
            let status = http?.statusCode
            let finalURL = http?.url?.absoluteString ?? url.absoluteString
            var body = String(data: data.prefix(200), encoding: .utf8) ?? ""
            if finalURL != url.absoluteString {
                body = "(重定向至 \(finalURL)) " + body
            }
            return (status, body.isEmpty ? nil : body)
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    private func sampleCourse() -> Course {
        Course(
            id: "TEST001",
            name: "測試課程",
            instructor: "測試教師",
            location: "測試教室",
            dayOfWeek: 1,
            startPeriod: 1,
            endPeriod: 2,
            color: "#007AFF"
        )
    }
}

// MARK: - Check-in Test View (Debug only)

struct CheckInTestView: View {
    private let mockRollcall = Rollcall(
        rollcall_id: 999999,
        course_id: 999,
        course_title: "(TEST) 輔大 AIO 測試課程",
        rollcall_status: "in_progress",
        source: "number",
        is_number: true,
        is_radar: false,
        is_expired: false,
        status: "absent",
        rollcall_time: "2026-04-27T06:00:00Z",
        title: "Debug 點名測試",
        created_by_name: "Debug Teacher",
        student_rollcall_id: 0
    )

    @State private var result: RollcallCheckInResult? = nil
    @State private var showManualEntry = false

    var body: some View {
        List {
            Section {
                Label("模擬模式：不會發送真實 API 請求", systemImage: "flask.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Section("模擬點名") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mockRollcall.course_title)
                                .font(.headline)
                            Text(mockRollcall.title)
                                .font(.caption).foregroundStyle(.secondary)
                            Text(mockRollcall.created_by_name)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("進行中")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.blue.opacity(0.15))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "number.circle.fill").font(.caption)
                        Text("數字碼點名").font(.caption)
                    }.foregroundStyle(.secondary)

                    if let result {
                        switch result {
                        case .success(let code):
                            Label("簽到成功！數字碼：\(code)", systemImage: "checkmark.circle.fill")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(.green)
                        case .failure(let msg):
                            Label(msg, systemImage: "xmark.circle.fill")
                                .font(.subheadline).foregroundStyle(.red)
                        }
                    } else {
                        Button { showManualEntry = true } label: {
                            Label("輸入數字碼", systemImage: "keyboard").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).tint(.pink)
                    }

                    if result != nil {
                        Button("重置測試") { result = nil }
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("說明") {
                Text("• 手動輸入：輸入 1234 會成功，其他會失敗")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("簽到 UI 測試")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showManualEntry) {
            ManualCheckInSheet(rollcall: mockRollcall) { code in
                showManualEntry = false
                result = (code == "1234") ? .success(code) : .failure("數字碼錯誤（提示：正確是 1234）")
            }
        }
    }
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
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
            .environment(\.fjuService, FJUService.shared)
            .environment(AuthenticationManager())
    }
}
