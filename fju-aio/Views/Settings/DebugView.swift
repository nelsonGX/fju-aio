import SwiftUI
import ActivityKit
import EventKit
import OSLog

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.nelsongx.apps.fju-aio", category: "Debug")

// MARK: - Collapsible Section

private struct CollapsibleSection<Content: View>: View {
    let title: String
    @State private var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    init(_ title: String, startExpanded: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self._isExpanded = State(initialValue: startExpanded)
        self.content = content
    }

    var body: some View {
        Section {
            if isExpanded {
                content()
            }
        } header: {
            Button {
                withAnimation { isExpanded.toggle() }
            } label: {
                HStack {
                    Text(title)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Info Row

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

// MARK: - Debug View

struct DebugView: View {
    @Environment(\.fjuService) private var service
    @Environment(AuthenticationManager.self) private var authManager
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true
    @AppStorage("attendance.hideLeaveDetails") private var hideLeaveDetails = true
    @State private var showOnboarding = false
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
    @State private var showDeleteFJUCalendarConfirm = false
    @State private var deleteCalendarResult: String?
    private let debugEventStore = EKEventStore()

    var body: some View {
        List {
            // MARK: 系統資訊
            CollapsibleSection("系統資訊", startExpanded: true) {
                InfoRow(label: "App 版本", value: "1.0.0")
                InfoRow(label: "Build", value: "1")
                InfoRow(label: "iOS 版本", value: UIDevice.current.systemVersion)
                InfoRow(label: "裝置型號", value: UIDevice.current.model)
                InfoRow(label: "裝置名稱", value: UIDevice.current.name)
            }

            // MARK: 認證狀態
            CollapsibleSection("認證狀態", startExpanded: true) {
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

            // MARK: TronClass Session
            CollapsibleSection("TronClass Session") {
                if let session = tronClassSession {
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
                } else {
                    Text("無 Session 資料")
                        .foregroundStyle(.secondary)
                }
            }

            // MARK: SIS Session
            CollapsibleSection("SIS（校務系統）Session") {
                if let session = sisSession {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("JWT Token（完整）")
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
                            Text("JWT Payload（解碼）")
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
                } else {
                    Text("無 Session 資料")
                        .foregroundStyle(.secondary)
                    Text("提示: 需要先登入才會有 SIS Session")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            // MARK: ESTU Session
            CollapsibleSection("ESTU（選課系統）Session") {
                if let session = estuSession {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ASP.NET Session ID")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(session.sessionId)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ViewState（前 100 字元）")
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
                        Text("EventValidation（前 100 字元）")
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
                } else {
                    Text("無 Session 資料")
                        .foregroundStyle(.secondary)
                    Text("提示: 需要先登入並訪問課表才會有 ESTU Session")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            // MARK: 服務狀態
            CollapsibleSection("服務狀態") {
                InfoRow(label: "服務類型", value: String(describing: type(of: service)))
                InfoRow(label: "可用學期", value: availableSemesters.joined(separator: ", "))
            }

            // MARK: 資料統計
            CollapsibleSection("資料統計") {
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

            // MARK: 課程詳情
            CollapsibleSection("課程詳情（\(courses.count) 筆）") {
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

            // MARK: 成績詳情
            CollapsibleSection("成績詳情（\(grades.count) 筆）") {
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

            // MARK: 作業詳情
            CollapsibleSection("作業詳情（\(assignments.count) 筆）") {
                ForEach(assignments) { assignment in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(assignment.title)
                            .font(.headline)
                        Text(assignment.courseName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("截止: \(assignment.dueDate.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // MARK: 出缺席統計
            CollapsibleSection("出缺席統計") {
                let presentCount = attendanceRecords.filter { $0.status == .present }.count
                let absentCount = attendanceRecords.filter { $0.status == .absent }.count
                let lateCount = attendanceRecords.filter { $0.status == .late }.count
                let excusedCount = attendanceRecords.filter { $0.status == .excused }.count
                InfoRow(label: "出席", value: "\(presentCount)")
                InfoRow(label: "缺席", value: "\(absentCount)")
                InfoRow(label: "遲到", value: "\(lateCount)")
                InfoRow(label: "請假", value: "\(excusedCount)")
                Toggle("隱藏其他同學的假別詳情", isOn: $hideLeaveDetails)
                    .font(.subheadline)
            }

            // MARK: 行事曆事件
            CollapsibleSection("行事曆事件（\(calendarEvents.count) 筆）") {
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

            // MARK: Live Activity 測試（即時）
            CollapsibleSection("Live Activity 測試（即時）") {
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

            // MARK: Live Activity 伺服器測試
            CollapsibleSection("Live Activity 伺服器測試") {
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

            // MARK: 通知紀錄
            if !notificationLog.isEmpty {
                CollapsibleSection("通知紀錄", startExpanded: true) {
                    ForEach(notificationLog.indices, id: \.self) { i in
                        Text(notificationLog[i])
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(notificationLog[i].hasPrefix("✅") ? .green :
                                             notificationLog[i].hasPrefix("❌") ? .red : .primary)
                            .listRowBackground(Color(.systemGroupedBackground))
                    }
                }
            }

            // MARK: 隱藏功能
            CollapsibleSection("隱藏功能", startExpanded: true) {
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

            // MARK: 行事曆（除錯）
            CollapsibleSection("行事曆（除錯）") {
                if let result = deleteCalendarResult {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(result.hasPrefix("✅") ? .green : .red)
                }
                Button("刪除「輔大行事曆」所有事件", role: .destructive) {
                    showDeleteFJUCalendarConfirm = true
                }
            }

            // MARK: Onboarding
            CollapsibleSection("Onboarding") {
                Button("重新顯示 Onboarding") {
                    showOnboarding = true
                }
                Button("重置 Onboarding 狀態", role: .destructive) {
                    hasCompletedOnboarding = false
                }
            }

            // MARK: 操作
            Section("操作") {
                Button("重新載入所有資料") {
                    Task { await loadAllData() }
                }
                .disabled(isLoading)

                Button("重新載入所有 Sessions") {
                    Task { await loadAllSessions() }
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
        .confirmationDialog(
            "將從「輔大行事曆」及預設行事曆中刪除所有與學期行事曆相符的事件",
            isPresented: $showDeleteFJUCalendarConfirm,
            titleVisibility: .visible
        ) {
            Button("刪除相符事件", role: .destructive) {
                deleteFJUCalendarEvents()
            }
            Button("取消", role: .cancel) {}
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView()
        }
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

    // MARK: - Private helpers

    private func deleteFJUCalendarEvents() {
        Task {
            do {
                let granted = try await debugEventStore.requestFullAccessToEvents()
                guard granted else {
                    await MainActor.run { deleteCalendarResult = "❌ 無法存取行事曆" }
                    return
                }
                let fjuName = "輔大行事曆"
                var searchCalendars: [EKCalendar] = []
                if let fjuCal = debugEventStore.calendars(for: .event).first(where: { $0.title == fjuName }) {
                    searchCalendars.append(fjuCal)
                }
                if let defaultCal = debugEventStore.defaultCalendarForNewEvents,
                   !searchCalendars.contains(where: { $0.calendarIdentifier == defaultCal.calendarIdentifier }) {
                    searchCalendars.append(defaultCal)
                }
                guard !searchCalendars.isEmpty else {
                    await MainActor.run { deleteCalendarResult = "❌ 找不到可搜尋的行事曆" }
                    return
                }
                let knownTitles = Set(calendarEvents.map { $0.title })
                guard !knownTitles.isEmpty else {
                    await MainActor.run { deleteCalendarResult = "❌ 沒有已載入的行事曆資料可比對，請先回到行事曆頁面載入資料" }
                    return
                }
                let start = Calendar.current.date(byAdding: .year, value: -2, to: Date()) ?? Date()
                let end = Calendar.current.date(byAdding: .year, value: 3, to: Date()) ?? Date()
                let predicate = debugEventStore.predicateForEvents(withStart: start, end: end, calendars: searchCalendars)
                let eventsToDelete = debugEventStore.events(matching: predicate).filter { knownTitles.contains($0.title) }
                for event in eventsToDelete {
                    try debugEventStore.remove(event, span: .thisEvent, commit: false)
                }
                try debugEventStore.commit()
                await MainActor.run {
                    deleteCalendarResult = "✅ 已刪除 \(eventsToDelete.count) 個輔大行事曆事件"
                }
            } catch {
                await MainActor.run {
                    deleteCalendarResult = "❌ \(error.localizedDescription)"
                }
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
            logger.info("載入資料時發生錯誤: \(error)")
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
            tronClassSession = try await authManager.getValidSession()
        } catch {
            logger.info("❌ 無法載入 TronClass Session: \(error)")
            sessionLoadError = "TronClass: \(error.localizedDescription)"
            tronClassSession = nil
        }
    }

    private func loadSISSession() async {
        do {
            sisSession = try await authManager.getValidSISSession()
        } catch {
            logger.info("❌ 無法載入 SIS Session: \(error)")
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
            estuSession = try await EstuAuthService.shared.getValidSession()
        } catch {
            logger.info("❌ 無法載入 ESTU Session: \(error)")
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
    @State private var selectedType: RollcallType = .number
    @State private var result: RollcallCheckInResult? = nil
    @State private var friendResults: [String: FriendCheckInStatus] = [:]
    @State private var showManualEntry = false
    @State private var showQRScanner = false
    @State private var simulateAlreadyCheckedIn = false
    @State private var pendingManualFriends: [FriendRecord] = []
    @State private var pendingQRFriends: [FriendRecord] = []

    @State private var credFriends: [FriendRecord] = []

    enum RollcallType: String, CaseIterable {
        case number = "數字碼"
        case radar  = "雷達"
        case qr     = "QR Code"
    }

    private var mockRollcall: Rollcall {
        Rollcall(
            rollcall_id: 999999,
            course_id: 999,
            course_title: "(TEST) 輔大 AIO 測試課程",
            rollcall_status: "in_progress",
            source: selectedType == .number ? "number" : selectedType == .radar ? "radar" : "qr",
            is_number: selectedType == .number,
            is_radar: selectedType == .radar,
            is_qr: selectedType == .qr,
            is_expired: false,
            status: simulateAlreadyCheckedIn ? "on_call" : "absent",
            rollcall_time: "2026-04-27T06:00:00Z",
            title: "Debug 點名測試（\(selectedType.rawValue)）",
            created_by_name: "Debug Teacher",
            student_rollcall_id: 0
        )
    }

    var body: some View {
        List {
            Section {
                Label("簽到不會送出真實請求，但認證朋友帳號會使用真實 API", systemImage: "flask.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Section("點名類型") {
                Picker("點名類型", selection: $selectedType) {
                    ForEach(RollcallType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedType) {
                    result = nil
                    friendResults = [:]
                }
            }

            Section("狀態") {
                Toggle("模擬自己已簽到", isOn: $simulateAlreadyCheckedIn)
                    .onChange(of: simulateAlreadyCheckedIn) {
                        result = nil
                        friendResults = [:]
                    }
            }

            Section("模擬點名") {
                RollcallRowView(
                    rollcall: mockRollcall,
                    result: result,
                    friendResults: friendResults,
                    proxyFriends: credFriends,
                    onManualEntry: { friends in
                        pendingManualFriends = friends
                        showManualEntry = true
                    },
                    onRadarCheckIn: {
                        simulateCheckin(includingFriends: [])
                    },
                    onQRCheckIn: {
                        pendingQRFriends = []
                        showQRScanner = true
                    },
                    onProxyRadarCheckIn: { friends in
                        simulateCheckin(includingFriends: friends)
                    },
                    onProxyQRCheckin: { sessions in
                        pendingQRFriends = sessions.map(\.0)
                        showQRScanner = true
                    }
                )
                .padding(.vertical, 4)
                .id("\(selectedType.rawValue)-\(simulateAlreadyCheckedIn)")

                if result != nil || !friendResults.isEmpty {
                    Button("重置測試") {
                        result = nil
                        friendResults = [:]
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section("說明") {
                Text("• 數字碼：輸入 1234 成功，其他失敗").font(.caption).foregroundStyle(.secondary)
                Text("• 雷達：模擬成功（不送請求）").font(.caption).foregroundStyle(.secondary)
                Text("• QR Code：掃描任何 QR 碼皆成功（不送請求）").font(.caption).foregroundStyle(.secondary)
                Text("• 群組：認證呼叫真實 API，點名不送請求").font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("簽到 UI 測試")
        .navigationBarTitleDisplayMode(.inline)
        .task { loadCredFriends() }
        .sheet(isPresented: $showManualEntry) {
            ManualCheckInSheet(rollcall: mockRollcall) { code in
                showManualEntry = false
                result = (code == "1234") ? .success(code) : .failure("數字碼錯誤（提示：正確是 1234）")
                simulateGroupCheckin(for: pendingManualFriends)
                pendingManualFriends = []
            }
        }
        .sheet(isPresented: $showQRScanner) {
            QRScannerSheet(rollcall: mockRollcall) { _ in
                showQRScanner = false
                result = .success(nil)
                simulateGroupCheckin(for: pendingQRFriends)
                pendingQRFriends = []
            }
        }
    }

    // MARK: - Helpers

    private func loadCredFriends() {
        credFriends = FriendStore.shared.credentialedFriends
    }

    private func simulateCheckin(includingFriends friends: [FriendRecord]) {
        result = .success(nil)
        simulateGroupCheckin(for: friends)
    }

    /// Mark selected friends as "simulated success" without sending any API request
    private func simulateGroupCheckin(for friends: [FriendRecord]) {
        for friend in friends {
            friendResults[friend.empNo] = .success
        }
    }
}

// MARK: - No-redirect URL session delegate

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
