import SwiftUI
import UniformTypeIdentifiers

struct LeaveRequestView: View {
    @State private var selectedTab: Tab = .history

    enum Tab: String, CaseIterable {
        case history = "歷史假單"
        case stats = "請假統計"
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("頁面", selection: $selectedTab) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            Group {
                switch selectedTab {
                case .history: LeaveHistoryView()
                case .stats:   LeaveStatsView()
                }
            }
        }
        .navigationTitle("請假申請")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    LeaveApplyWizard()
                        .navigationTitle("申請假單")
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("申請假單")
            }
        }
    }
}

// MARK: - History Tab

private struct LeaveHistoryView: View {
    private let leaveService = LeaveService.shared
    @State private var academicYears: [HyRecord] = []
    @State private var selectedHy: HyRecord?
    @State private var selectedHt: Int = 2
    @State private var records: [LeaveRecord] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var recordToCancel: LeaveRecord?
    @State private var isCancelling = false
    @State private var cancelErrorMessage: String?

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    var body: some View {
        content
            .task { await loadInitial() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView("載入中…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = errorMessage {
            ContentUnavailableView(
                "載入失敗",
                systemImage: "exclamationmark.triangle",
                description: Text(error)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                Section {
                    Picker("學年度", selection: $selectedHy) {
                        ForEach(academicYears) { hy in
                            Text(hy.hyNa).tag(Optional(hy))
                        }
                    }
                    Picker("學期", selection: $selectedHt) {
                        Text("第 1 學期").tag(1)
                        Text("第 2 學期").tag(2)
                    }
                }
                .onChange(of: selectedHy) { _, _ in records = []; Task { await loadRecords() } }
                .onChange(of: selectedHt) { _, _ in records = []; Task { await loadRecords() } }

                Section(records.isEmpty ? "尚無記錄" : "\(records.count) 筆記錄") {
                    if records.isEmpty {
                        Text("尚無請假紀錄").foregroundStyle(.secondary)
                    } else {
                        ForEach(records, id: \.id) { record in
                            LeaveRecordRow(record: record, dateFormatter: dateFormatter) {
                                recordToCancel = record
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable { await loadRecords() }
        }
    }

    // placeholder to attach modifiers below
    private var alertModifiers: some View { EmptyView() }

    // keep the alert modifiers on the outer body — re-attach via wrapper below
    // Actually we'll attach them inline:
    private var bodyWithAlerts: some View {
        content
            .task { await loadInitial() }
        .alert("確認取消假單", isPresented: Binding(
            get: { recordToCancel != nil },
            set: { if !$0 { recordToCancel = nil } }
        )) {
            Button("取消假單", role: .destructive) {
                if let record = recordToCancel {
                    Task { await cancelRecord(record) }
                }
            }
            Button("返回", role: .cancel) { recordToCancel = nil }
        } message: {
            if let record = recordToCancel {
                Text("確定要取消 \(record.leaveNa) 假單（\(record.applyNo)）嗎？")
            }
        }
        .alert("取消失敗", isPresented: Binding(
            get: { cancelErrorMessage != nil },
            set: { if !$0 { cancelErrorMessage = nil } }
        )) {
            Button("確定", role: .cancel) { cancelErrorMessage = nil }
        } message: {
            Text(cancelErrorMessage ?? "")
        }
    }

    private func loadInitial() async {
        isLoading = true
        errorMessage = nil
        do {
            academicYears = try await leaveService.fetchAcademicYears()
            selectedHy = academicYears.first
        } catch is CancellationError {
            isLoading = false
            return
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return
        }
        await loadRecords()
    }

    private func loadRecords() async {
        guard let hy = selectedHy else { return }
        isLoading = records.isEmpty   // only show spinner on first load, not on refresh
        errorMessage = nil
        do {
            let fetched = try await leaveService.fetchLeaveRecords(academicYear: hy.hy, semester: selectedHt)
            records = fetched
        } catch is CancellationError {
            // Silently ignore task cancellation (e.g. pull-to-refresh interrupted).
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func cancelRecord(_ record: LeaveRecord) async {
        isCancelling = true
        do {
            try await leaveService.cancelLeave(leaveApplySn: record.leaveApplySn)
            records.removeAll { $0.leaveApplySn == record.leaveApplySn }
        } catch {
            cancelErrorMessage = error.localizedDescription
        }
        isCancelling = false
        recordToCancel = nil
    }
}

private struct LeaveRecordRow: View {
    let record: LeaveRecord
    let dateFormatter: DateFormatter
    let onCancel: () -> Void

    private var beginDate: Date? { dateFormatter.date(from: record.beginDate) }
    private var endDate: Date? { dateFormatter.date(from: record.endDate) }

    private var displayDateRange: String {
        let display = DateFormatter()
        display.dateFormat = "M/d"
        guard let s = beginDate, let e = endDate else { return record.beginDate }
        let start = display.string(from: s)
        let end = display.string(from: e)
        return start == end ? start : "\(start)–\(end)"
    }

    private var statusColor: Color {
        switch record.applyStatus {
        case 9: return .green
        case 5: return .red
        default: return .orange
        }
    }

    // Draft (0=編輯中) and pending (1=待審) records can be cancelled
    private var canCancel: Bool { record.applyStatus == 0 || record.applyStatus == 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.leaveNa)
                        .font(.body.weight(.semibold))
                    Text("假單號：\(record.applyNo)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(record.applyStatusNa)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .foregroundStyle(statusColor)
                    .background(statusColor.opacity(0.12), in: Capsule())
            }

            HStack(spacing: 16) {
                Label(displayDateRange, systemImage: "calendar")
                Label("\(record.beginSectNa)–\(record.endSectNa)", systemImage: "clock")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !record.leaveReason.isEmpty {
                Text(record.leaveReason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack {
                Text("共 \(record.totalDay) 天 \(record.totalSect) 節")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer()

                if canCancel {
                    Button("取消假單", role: .destructive, action: onCancel)
                        .font(.caption)
                        .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Apply Tab — 4-Step Wizard

private struct LeaveApplyWizard: View {
    private let leaveService = LeaveService.shared

    // Wizard navigation
    @State private var step: Int = 0           // 0=rules modal, 1–4 = wizard steps
    @State private var showRulesModal = true

    // Reference data (fetched on load)
    @State private var isLoadingRef = true
    @State private var loadRefError: String?
    @State private var academicYears: [HyRecord] = []
    @State private var leaveSubtypes: [LeaveKind] = []        // 事假, 病假, …
    @State private var sections: [CourseSection] = []
    @State private var famTypes: [FamTypeItem] = []
    @State private var famLevels: [FamLevelItem] = []

    // Wizard draft shared across steps
    @State private var draft = LeaveWizardDraft()

    // Step 3 data
    @State private var selCouCourses: [LeaveSelCouCourse] = []
    @State private var selectedEntries: Set<String> = []      // key = "\(jonCouSn)-\(couDate)-\(sectNo)"

    // Step 3/4 loading
    @State private var isProcessing = false
    @State private var processError: String?

    // After wizard completes
    @State private var didSubmit = false
    @State private var submittedApplyNo = ""

    var body: some View {
        Group {
            if isLoadingRef {
                ProgressView("載入中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadRefError {
                VStack(spacing: 12) {
                    Text("載入失敗：\(error)")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("重試") { Task { await loadRef() } }
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if didSubmit {
                SubmitSuccessView(applyNo: submittedApplyNo) {
                    // Reset wizard to start a new application
                    draft = LeaveWizardDraft()
                    selCouCourses = []
                    selectedEntries = []
                    didSubmit = false
                    step = 1
                    showRulesModal = false
                }
            } else {
                wizardContent
            }
        }
        .task { await loadRef() }
        .sheet(isPresented: $showRulesModal) {
            LeaveRulesModal {
                showRulesModal = false
                step = 1
            }
        }
    }

    @ViewBuilder
    private var wizardContent: some View {
        VStack(spacing: 0) {
            // Step indicator
            StepIndicator(current: step, total: 4)
                .padding(.horizontal)
                .padding(.vertical, 10)

            Divider()

            // Step content
            ScrollView {
                switch step {
                case 1:
                    Step1CategoryView(draft: $draft)
                        .padding()
                case 2:
                    Step2FormView(
                        draft: $draft,
                        academicYears: academicYears,
                        leaveSubtypes: leaveSubtypes,
                        sections: sections,
                        famTypes: famTypes,
                        famLevels: famLevels
                    )
                    .padding()
                case 3:
                    Step3CoursesView(
                        courses: selCouCourses,
                        selectedEntries: $selectedEntries,
                        sections: sections
                    )
                    .padding()
                case 4:
                    Step4ConfirmView(
                        draft: draft,
                        courses: selCouCourses,
                        selectedEntries: selectedEntries,
                        sections: sections
                    )
                    .padding()
                default:
                    EmptyView()
                }
            }

            if let err = processError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.top, 4)
            }

            Divider()

            // Navigation buttons
            HStack(spacing: 16) {
                if step > 1 {
                    Button("上一步") {
                        // Going back to Step 1 means the category may change → discard draft
                        if step == 2 {
                            draft.leaveApplySn = 0
                            draft.applyNo = ""
                        }
                        withAnimation { step -= 1 }
                        processError = nil
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                if step < 4 {
                    Button {
                        Task { await advanceStep() }
                    } label: {
                        if isProcessing {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("下一步")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isProcessing || !canAdvance)
                } else {
                    Button {
                        Task { await finalSubmit() }
                    } label: {
                        if isProcessing {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("送出").bold()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isProcessing)
                }
            }
            .padding()
        }
    }

    // MARK: - Validation

    private var canAdvance: Bool {
        switch step {
        case 1: return true
        case 2:
            return !draft.beginDate.isEmpty &&
                   !draft.endDate.isEmpty &&
                   !draft.leaveReason.trimmingCharacters(in: .whitespaces).isEmpty &&
                   !draft.phoneNumber.trimmingCharacters(in: .whitespaces).isEmpty &&
                   isValidEmail(draft.emailAccount)
        case 3: return true   // Can proceed even with no courses selected
        default: return true
        }
    }

    private func isValidEmail(_ email: String) -> Bool {
        let t = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.contains("@") && t.contains(".")
    }

    // MARK: - Navigation logic

    private func advanceStep() async {
        processError = nil
        switch step {
        case 2:
            isProcessing = true
            do {
                let sn: Int
                if draft.leaveApplySn > 0 {
                    // Already created on a previous forward pass — reuse it, don't create another
                    sn = draft.leaveApplySn
                } else {
                    // POST /StuLeave to create the draft record
                    sn = try await leaveService.submitLeave(
                        academicYear: draft.hy,
                        semester: draft.ht,
                        leaveKind: draft.leaveKind,
                        examKind: 0,
                        refLeaveSn: draft.refLeaveSn,
                        beginDate: draft.beginDate,
                        endDate: draft.endDate,
                        beginSectNo: draft.beginSectNo,
                        endSectNo: draft.endSectNo,
                        reason: draft.leaveReason,
                        phoneNumber: draft.phoneNumber,
                        emailAccount: draft.emailAccount,
                        proofFileData: draft.proofFileData,
                        proofFileExt: draft.proofFileExt
                    )
                    draft.leaveApplySn = sn
                }
                // Fetch (or re-fetch) matched courses
                selCouCourses = try await leaveService.fetchSelCouCourses(leaveApplySn: sn)
                // Pre-select all matched dates
                selectedEntries = Set(selCouCourses.flatMap { course in
                    course.leaveDates.map { d in entryKey(course: course, date: d) }
                })
                withAnimation { step = 3 }
            } catch {
                processError = error.localizedDescription
            }
            isProcessing = false
        case 3:
            // POST /StuLeave/{sn}/SelCou with selected entries
            isProcessing = true
            do {
                let session = try await SISAuthService.shared.getValidSession()
                let entries = buildSelCouEntries(stuNo: session.empNo)
                try await leaveService.selectCourses(entries, forLeave: draft.leaveApplySn)
                withAnimation { step = 4 }
            } catch {
                processError = error.localizedDescription
            }
            isProcessing = false
        default:
            withAnimation { step += 1 }
        }
    }

    private func finalSubmit() async {
        processError = nil
        isProcessing = true
        do {
            try await leaveService.confirmLeave(leaveApplySn: draft.leaveApplySn)
            submittedApplyNo = draft.applyNo.isEmpty ? "\(draft.leaveApplySn)" : draft.applyNo
            didSubmit = true
        } catch {
            processError = error.localizedDescription
        }
        isProcessing = false
    }

    // MARK: - Helpers

    private func entryKey(course: LeaveSelCouCourse, date: LeaveSelCouDate) -> String {
        "\(course.jonCouSn)-\(date.couDate)-\(date.sectNo)"
    }

    private func buildSelCouEntries(stuNo: String) -> [SelCouPostEntry] {
        // One entry per course. Each entry contains all selected seqTims + all unique couDates.
        selCouCourses.compactMap { course in
            let selectedDates = course.leaveDates.filter {
                selectedEntries.contains(entryKey(course: course, date: $0))
            }
            guard !selectedDates.isEmpty else { return nil }

            // seqTims: one item per selected date+period
            let seqTims = selectedDates.map { d in
                let sectionName = sections.first { $0.sectNo == d.sectNo }?.sectNa ?? "D\(d.sectNo)"
                return SelCouSeqTim(
                    section: sectionName,
                    leaveSeqTimSn: 0,
                    leaveApplySn: draft.leaveApplySn,
                    jonCouSn: course.jonCouSn,
                    avaCouSn: course.avaCouSn,
                    stuNo: stuNo,
                    couDate: d.couDate + "T00:00:00",
                    couWek: course.couWek,
                    sectNo: d.sectNo
                )
            }

            // couDates: plain date strings, one per unique date
            let couDates = Array(Set(selectedDates.map { $0.couDate + "T00:00:00" })).sorted()

            return SelCouPostEntry(
                jonCouSn: course.jonCouSn,
                avaCouSn: course.avaCouSn,
                stuNo: stuNo,
                couWek: course.couWek,
                seqTims: seqTims,
                couDates: couDates
            )
        }
    }

    // MARK: - Reference data load

    private func loadRef() async {
        isLoadingRef = true
        loadRefError = nil
        do {
            async let hyTask       = leaveService.fetchAcademicYears()
            async let subtypeTask  = leaveService.fetchRefLeave()
            async let sectTask     = leaveService.fetchCourseSections()
            async let famTypeTask  = leaveService.fetchFamTypes()
            async let famLevelTask = leaveService.fetchFamLevels()
            async let contactTask  = leaveService.fetchStudentContact()

            academicYears  = try await hyTask
            leaveSubtypes  = try await subtypeTask
            sections       = try await sectTask
            famTypes       = (try? await famTypeTask) ?? []
            famLevels      = (try? await famLevelTask) ?? []

            // Set defaults from fetched data
            if let firstHy = academicYears.first {
                draft.hy = firstHy.hy
                draft.ht = 2
            }
            if let firstSubtype = leaveSubtypes.first {
                draft.refLeaveSn = firstSubtype.value
            }
            if sections.count >= 2 {
                draft.beginSectNo = sections.first?.sectNo ?? 1
                draft.endSectNo   = sections.last?.sectNo ?? 9
            }

            // Default dates to today so the button is enabled without requiring picker interaction
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            df.locale = Locale(identifier: "en_US_POSIX")
            let today = df.string(from: Date())
            if draft.beginDate.isEmpty { draft.beginDate = today }
            if draft.endDate.isEmpty   { draft.endDate   = today }

            // Pre-fill contact info
            if let contact = try? await contactTask {
                if draft.phoneNumber.isEmpty { draft.phoneNumber = contact.phoneNumber ?? "" }
                if draft.emailAccount.isEmpty { draft.emailAccount = contact.emailAccount ?? "" }
            }

        } catch {
            loadRefError = error.localizedDescription
        }
        isLoadingRef = false
    }
}

// MARK: - Rules Modal (Step 0)

private struct LeaveRulesModal: View {
    let onAcknowledge: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("第二十六條")
                        .font(.headline)
                    Text("學生請假，事假、普通傷病假以曠課時數計，不得超過各科目學期上課總時數三分之一，超過者依學則規定辦理。")
                        .foregroundStyle(.secondary)

                    Text("第二十七條")
                        .font(.headline)
                    Text("學生未依規定辦理請假手續或逾假未到者，以曠課論。學期曠課達上課總時數三分之一者，不得參加期末考試，並應依學則規定辦理。")
                        .foregroundStyle(.red)
                        .padding()
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
                .padding()
            }
            .navigationTitle("學生請假規則")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button {
                    onAcknowledge()
                } label: {
                    Text("我已瞭解請假相關規定")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding()
                .background(.regularMaterial)
            }
        }
    }
}

// MARK: - Step Indicator

private struct StepIndicator: View {
    let current: Int
    let total: Int

    private let labels = ["選擇性質", "填寫內容", "選課程", "確認送出"]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(1...total, id: \.self) { n in
                HStack(spacing: 0) {
                    VStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .fill(n <= current ? Color.accentColor : Color.secondary.opacity(0.25))
                                .frame(width: 28, height: 28)
                            if n < current {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                            } else {
                                Text("\(n)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(n == current ? .white : .secondary)
                            }
                        }
                        Text(labels[n - 1])
                            .font(.system(size: 10))
                            .foregroundStyle(n == current ? .primary : .secondary)
                    }
                    if n < total {
                        Rectangle()
                            .fill(n < current ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(height: 2)
                            .padding(.bottom, 18)
                    }
                }
                if n < total { Spacer(minLength: 0) }
            }
        }
    }
}

// MARK: - Step 1: 選擇請假性質

private struct Step1CategoryView: View {
    @Binding var draft: LeaveWizardDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("請擇一申請")
                .font(.headline)

            VStack(spacing: 12) {
                categoryButton(kind: 1, title: "一般請假", subtitle: "事假、病假、喪假等")
                categoryButton(kind: 2, title: "考試請假", subtitle: "期中考、期末考等考試期間")
            }

            if draft.leaveKind == 1 {
                VStack(alignment: .leading, spacing: 8) {
                    Label("一般請假注意事項", systemImage: "info.circle")
                        .font(.subheadline.weight(.semibold))

                    Text("• 請假需於規定時間內申請，逾期無法補登。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("• 公假及考試假不適用此流程，請洽各系辦公室。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("• 日間部諮詢：02-29052231　進修部：02-29052247")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    @ViewBuilder
    private func categoryButton(kind: Int, title: String, subtitle: String) -> some View {
        Button {
            draft.leaveKind = kind
        } label: {
            HStack(spacing: 14) {
                Image(systemName: draft.leaveKind == kind ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(draft.leaveKind == kind ? Color.accentColor : Color.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(draft.leaveKind == kind ? Color.accentColor.opacity(0.08) : Color(uiColor: .secondarySystemGroupedBackground))
                    .stroke(draft.leaveKind == kind ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Step 2: 填寫假單詳細內容

private struct Step2FormView: View {
    @Binding var draft: LeaveWizardDraft
    let academicYears: [HyRecord]
    let leaveSubtypes: [LeaveKind]
    let sections: [CourseSection]
    let famTypes: [FamTypeItem]
    let famLevels: [FamLevelItem]

    @State private var showDocPicker = false

    // Helper: does the selected subtype require family relationship fields?
    private var isBereavementLeave: Bool {
        leaveSubtypes.first { $0.value == draft.refLeaveSn }?.requiresFamilyFields ?? false
    }

    private var selectedSubtypeLabel: String {
        leaveSubtypes.first { $0.value == draft.refLeaveSn }?.label ?? "—"
    }

    // Date formatter for display/API
    private let df: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private var beginDateBinding: Binding<Date> {
        Binding(
            get: { df.date(from: draft.beginDate) ?? Date() },
            set: { draft.beginDate = df.string(from: $0)
                   // Cascade end date if it falls before begin
                   if let end = df.date(from: draft.endDate), end < $0 {
                       draft.endDate = df.string(from: $0)
                   }
            }
        )
    }

    private var endDateBinding: Binding<Date> {
        Binding(
            get: { df.date(from: draft.endDate) ?? Date() },
            set: { draft.endDate = df.string(from: $0) }
        )
    }

    private var beginDateLower: Date { df.date(from: draft.beginDate) ?? Date() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            HStack(spacing: 16) {
                infoChip(label: "學年度", value: "\(draft.hy)")
                infoChip(label: "學期", value: "第 \(draft.ht) 學期")
                infoChip(label: "性質", value: draft.leaveKind == 1 ? "一般" : "考試")
            }
            .padding(.bottom, 16)

            // Academic year / semester
            VStack(alignment: .leading, spacing: 12) {
                formLabel("學年度 / 學期")
                HStack(spacing: 12) {
                    Picker("學年度", selection: $draft.hy) {
                        ForEach(academicYears) { hy in
                            Text(hy.hyNa).tag(hy.hy)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))

                    Picker("學期", selection: $draft.ht) {
                        Text("第 1 學期").tag(1)
                        Text("第 2 學期").tag(2)
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.bottom, 16)

            // Leave subtype (假別)
            VStack(alignment: .leading, spacing: 8) {
                formLabel("假別")
                Picker("假別", selection: $draft.refLeaveSn) {
                    ForEach(leaveSubtypes) { subtype in
                        Text(subtype.label).tag(subtype.value)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))

                // Bereavement extra fields
                if isBereavementLeave {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("親屬關係類型").font(.caption).foregroundStyle(.secondary)
                            Picker("類型", selection: Binding(
                                get: { draft.famTypeNo ?? 0 },
                                set: { draft.famTypeNo = $0 == 0 ? nil : $0 }
                            )) {
                                Text("請選擇").tag(0)
                                ForEach(famTypes) { t in Text(t.label).tag(t.value) }
                            }
                            .pickerStyle(.menu)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("親屬關係等級").font(.caption).foregroundStyle(.secondary)
                            Picker("等級", selection: Binding(
                                get: { draft.famLevelNo ?? 0 },
                                set: { draft.famLevelNo = $0 == 0 ? nil : $0 }
                            )) {
                                Text("請選擇").tag(0)
                                ForEach(famLevels) { l in Text(l.label).tag(l.value) }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                }
            }
            .padding(.bottom, 16)

            // Start date + section
            VStack(alignment: .leading, spacing: 8) {
                formLabel("開始時間")
                HStack(spacing: 12) {
                    DatePicker("", selection: beginDateBinding, displayedComponents: .date)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)

                    Picker("開始節次", selection: $draft.beginSectNo) {
                        ForEach(sections) { s in
                            Text(s.displayLabel).tag(s.sectNo)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity)
                    .onChange(of: draft.beginSectNo) { _, v in
                        if draft.endSectNo < v { draft.endSectNo = v }
                    }
                }
            }
            .padding(.bottom, 16)

            // End date + section
            VStack(alignment: .leading, spacing: 8) {
                formLabel("結束時間")
                HStack(spacing: 12) {
                    DatePicker("", selection: endDateBinding, in: beginDateLower..., displayedComponents: .date)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)

                    Picker("結束節次", selection: $draft.endSectNo) {
                        ForEach(sections.filter { $0.sectNo >= draft.beginSectNo }) { s in
                            Text(s.displayLabel).tag(s.sectNo)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 16)

            // Contact
            VStack(alignment: .leading, spacing: 8) {
                formLabel("聯絡資料")
                HStack {
                    Image(systemName: "phone")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    TextField("聯絡電話（必填）", text: $draft.phoneNumber)
                        .keyboardType(.phonePad)
                }
                .padding(10)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))

                HStack {
                    Image(systemName: "envelope")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    TextField("電子郵件信箱（必填）", text: $draft.emailAccount)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                .padding(10)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(.bottom, 16)

            // Reason
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    formLabel("請假事由")
                    Spacer()
                    Text("\(draft.leaveReason.count)/500")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                TextField("請填寫請假原因（必填）", text: $draft.leaveReason, axis: .vertical)
                    .lineLimit(4...8)
                    .onChange(of: draft.leaveReason) { _, v in
                        if v.count > 500 { draft.leaveReason = String(v.prefix(500)) }
                    }
                    .padding(10)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(.bottom, 16)

            // Supporting document
            VStack(alignment: .leading, spacing: 8) {
                formLabel("佐證文件")
                Text("請假類別：\(selectedSubtypeLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !draft.proofFileName.isEmpty {
                    HStack {
                        Label(draft.proofFileName, systemImage: "doc.fill")
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()
                        Button(role: .destructive) {
                            draft.proofFileData = nil
                            draft.proofFileName = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(10)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                } else {
                    Button {
                        showDocPicker = true
                    } label: {
                        Label("選擇佐證文件（選填）", systemImage: "paperclip")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .fileImporter(
            isPresented: $showDocPicker,
            allowedContentTypes: [.pdf, .image, .jpeg, .png],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) {
                let ext = url.pathExtension.lowercased()
                draft.proofFileData  = data
                draft.proofFileExt   = ext.isEmpty ? "pdf" : ext
                draft.proofFileName  = url.lastPathComponent
            }
        }
    }

    @ViewBuilder
    private func formLabel(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
    }

    @ViewBuilder
    private func infoChip(label: String, value: String) -> some View {
        VStack(spacing: 1) {
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
            Text(value).font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.1), in: Capsule())
    }
}

// MARK: - Step 3: 勾選請假課程

private struct Step3CoursesView: View {
    let courses: [LeaveSelCouCourse]
    @Binding var selectedEntries: Set<String>
    let sections: [CourseSection]

    private let dayNames = ["", "一", "二", "三", "四", "五", "六", "日"]

    private var eligibleCourses: [LeaveSelCouCourse] {
        courses.filter { !$0.leaveDates.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if eligibleCourses.isEmpty {
                ContentUnavailableView(
                    "無符合課程",
                    systemImage: "calendar.badge.checkmark",
                    description: Text("此請假時段內沒有排課，可直接前往下一步。")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                Text("選課清單  共 \(eligibleCourses.count) 門課")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ForEach(Array(eligibleCourses.enumerated()), id: \.element.id) { idx, course in
                    CourseCardView(
                        index: idx + 1,
                        course: course,
                        selectedEntries: $selectedEntries,
                        sections: sections,
                        dayNames: dayNames
                    )
                }
            }
        }
    }
}

private struct CourseCardView: View {
    let index: Int
    let course: LeaveSelCouCourse
    @Binding var selectedEntries: Set<String>
    let sections: [CourseSection]
    let dayNames: [String]

    private var hasMatchingDates: Bool { !course.leaveDates.isEmpty }

    private var allSelected: Bool {
        course.leaveDates.allSatisfy { d in
            selectedEntries.contains(entryKey(d))
        }
    }

    private func entryKey(_ d: LeaveSelCouDate) -> String {
        "\(course.jonCouSn)-\(d.couDate)-\(d.sectNo)"
    }

    private func dayLabel(_ wek: String) -> String {
        let n = Int(wek) ?? 0
        guard n >= 1 && n <= 7 else { return "" }
        return "每週\(dayNames[n])"
    }

    private func sectLabel(_ no: Int) -> String {
        sections.first { $0.sectNo == no }?.sectNa ?? "D\(no)"
    }

    private func shortDate(_ isoStr: String) -> String {
        let trimmed = isoStr.hasPrefix("2") ? String(isoStr.prefix(10)) : isoStr
        return trimmed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack {
                Text("\(index)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Color.accentColor, in: Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text(course.couCNa)
                        .font(.subheadline.weight(.semibold))
                    Text(course.couNo)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if hasMatchingDates {
                    Button {
                        if allSelected {
                            course.leaveDates.forEach { selectedEntries.remove(entryKey($0)) }
                        } else {
                            course.leaveDates.forEach { selectedEntries.insert(entryKey($0)) }
                        }
                    } label: {
                        Image(systemName: allSelected ? "checkmark.square.fill" : "square")
                            .foregroundStyle(allSelected ? .yellow : .secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(10)
            .background(Color.accentColor.opacity(0.08))

            // Details
            VStack(alignment: .leading, spacing: 6) {
                if let dptGrdNa = course.dptGrdNa {
                    infoRow(icon: "building.2", text: dptGrdNa)
                }
                if let tchCNa = course.tchCNa {
                    infoRow(icon: "person", text: tchCNa)
                }

                HStack {
                    Image(systemName: "clock").foregroundStyle(.secondary).frame(width: 16)
                    Text(dayLabel(course.couWek))
                        .font(.caption)
                    ForEach(course.sectNos, id: \.self) { sno in
                        Text(sectLabel(sno))
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }
                }

                // Leave date pills
                if hasMatchingDates {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar.badge.checkmark")
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        FlowLayout(spacing: 6) {
                            ForEach(course.leaveDates) { d in
                                let key = entryKey(d)
                                let isOn = selectedEntries.contains(key)
                                Button {
                                    if isOn { selectedEntries.remove(key) }
                                    else    { selectedEntries.insert(key) }
                                } label: {
                                    HStack(spacing: 3) {
                                        Text(shortDate(d.couDate))
                                            .font(.caption2)
                                        Image(systemName: isOn ? "checkmark" : "plus")
                                            .font(.system(size: 9, weight: .bold))
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .foregroundStyle(isOn ? .white : .accentColor)
                                    .background(isOn ? Color.accentColor : Color.accentColor.opacity(0.12), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                } else {
                    Text("請假日期：—")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(10)
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func infoRow(icon: String, text: String) -> some View {
        HStack {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 16)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Simple flow layout for date pills

private struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var height: CGFloat = 0
        var x: CGFloat = 0
        var rowH: CGFloat = 0
        for v in subviews {
            let size = v.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                height += rowH + spacing
                x = 0
                rowH = 0
            }
            rowH = max(rowH, size.height)
            x += size.width + spacing
        }
        height += rowH
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowH: CGFloat = 0
        for v in subviews {
            let size = v.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += rowH + spacing
                x = bounds.minX
                rowH = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            rowH = max(rowH, size.height)
            x += size.width + spacing
        }
    }
}

// MARK: - Step 4: 確認假單內容

private struct Step4ConfirmView: View {
    let draft: LeaveWizardDraft
    let courses: [LeaveSelCouCourse]
    let selectedEntries: Set<String>
    let sections: [CourseSection]

    private let dayNames = ["", "一", "二", "三", "四", "五", "六", "日"]

    private func sectLabel(_ no: Int) -> String {
        sections.first { $0.sectNo == no }?.sectNa ?? "D\(no)"
    }

    private func sectTimeLabel(_ no: Int) -> String {
        guard let s = sections.first(where: { $0.sectNo == no }) else { return "" }
        return "\(s.sectNa) : \(s.beginTime)–\(s.endTime)"
    }

    private func dayOfWeekLabel(_ dateStr: String) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        guard let d = df.date(from: dateStr) else { return "" }
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: d)
        // weekday: 1=Sun…7=Sat; map to Mon=一…Sun=日
        let idx = weekday == 1 ? 7 : weekday - 1
        return "星期\(dayNames[idx])"
    }

    private var selectedCourseList: [(course: LeaveSelCouCourse, dates: [LeaveSelCouDate])] {
        courses.compactMap { course in
            let filtered = course.leaveDates.filter { d in
                selectedEntries.contains("\(course.jonCouSn)-\(d.couDate)-\(d.sectNo)")
            }
            return filtered.isEmpty ? nil : (course, filtered)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Left/right columns summary
            VStack(alignment: .leading, spacing: 12) {
                Group {
                    confirmRow(label: "學年度", value: "\(draft.hy)")
                    confirmRow(label: "學期", value: "第 \(draft.ht) 學期")
                    confirmRow(label: "請假性質", value: draft.leaveKind == 1 ? "一般請假" : "考試請假")
                }
                Divider()
                Group {
                    HStack {
                        Text("開始時間").foregroundStyle(.secondary).font(.subheadline)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(draft.beginDate)
                                Text(dayOfWeekLabel(draft.beginDate))
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                            }
                            Text(sectTimeLabel(draft.beginSectNo))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Text("結束時間").foregroundStyle(.secondary).font(.subheadline)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(draft.endDate)
                                Text(dayOfWeekLabel(draft.endDate))
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                            }
                            Text(sectTimeLabel(draft.endSectNo))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Divider()
                Group {
                    confirmRow(label: "聯絡電話", value: draft.phoneNumber)
                    confirmRow(label: "電子郵件", value: draft.emailAccount)
                }
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("請假事由").foregroundStyle(.secondary).font(.subheadline)
                    Text(draft.leaveReason)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("佐證文件").foregroundStyle(.secondary).font(.subheadline)
                    if draft.proofFileName.isEmpty {
                        Text("未上傳").foregroundStyle(.tertiary).font(.caption)
                    } else {
                        Label(draft.proofFileName, systemImage: "doc.fill")
                            .font(.caption)
                    }
                }
            }
            .padding()
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))

            // Selected courses
            if !selectedCourseList.isEmpty {
                Text("請假課程  共 \(selectedCourseList.count) 門")
                    .font(.subheadline.weight(.semibold))

                ForEach(Array(selectedCourseList.enumerated()), id: \.offset) { idx, entry in
                    ConfirmCourseCard(
                        index: idx + 1,
                        course: entry.course,
                        dates: entry.dates,
                        sections: sections,
                        dayNames: dayNames
                    )
                }
            } else {
                Label("未選取任何課程", systemImage: "calendar.badge.minus")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    @ViewBuilder
    private func confirmRow(label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary).font(.subheadline)
            Spacer()
            Text(value).font(.subheadline.weight(.medium))
        }
    }
}

private struct ConfirmCourseCard: View {
    let index: Int
    let course: LeaveSelCouCourse
    let dates: [LeaveSelCouDate]
    let sections: [CourseSection]
    let dayNames: [String]

    private func sectLabel(_ no: Int) -> String {
        sections.first { $0.sectNo == no }?.sectNa ?? "D\(no)"
    }

    private func shortDate(_ isoStr: String) -> String {
        String(isoStr.prefix(10))
    }

    private func dayLabel(_ wek: String) -> String {
        let n = Int(wek) ?? 0
        guard n >= 1 && n <= 7 else { return "" }
        return "週\(dayNames[n])"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(index)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Color.green, in: Circle())
                Text(course.couCNa).font(.subheadline.weight(.semibold))
                Spacer()
                Text(course.couNo).font(.caption2).foregroundStyle(.secondary)
            }
            if let tchCNa = course.tchCNa {
                Label(tchCNa, systemImage: "person")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                Text(dayLabel(course.couWek)).font(.caption)
                ForEach(course.sectNos, id: \.self) { sno in
                    Text(sectLabel(sno))
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
            }
            FlowLayout(spacing: 4) {
                ForEach(dates) { d in
                    Text(shortDate(d.couDate))
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .foregroundStyle(.white)
                        .background(Color.green, in: Capsule())
                }
            }
        }
        .padding(10)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.green.opacity(0.3), lineWidth: 1))
    }
}

// MARK: - Submit Success View

private struct SubmitSuccessView: View {
    let applyNo: String
    let onNewApplication: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)
            Text("假單送出成功")
                .font(.title2.weight(.semibold))
            Text("假單號：\(applyNo)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("假單已送出，請等待各級主管審核。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button("再申請一筆") {
                onNewApplication()
            }
            .buttonStyle(.borderedProminent)
            .padding(.bottom)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Stats Tab

private struct LeaveStatsView: View {
    private let leaveService = LeaveService.shared

    @State private var academicYears: [HyRecord] = []
    @State private var selectedHy: HyRecord?
    @State private var selectedHt: Int = 2
    @State private var statSummary: LeaveStatSummary?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var deadline: String?

    private var stats: [LeaveStatRecord] {
        statSummary?.statLeaveCouList ?? []
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("載入中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                ContentUnavailableView(
                    "載入失敗",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section {
                        Picker("學年度", selection: $selectedHy) {
                            ForEach(academicYears) { hy in
                                Text(hy.hyNa).tag(Optional(hy))
                            }
                        }
                        Picker("學期", selection: $selectedHt) {
                            Text("第 1 學期").tag(1)
                            Text("第 2 學期").tag(2)
                        }
                    }
                    .onChange(of: selectedHy) { _, _ in statSummary = nil; Task { await loadStats() } }
                    .onChange(of: selectedHt) { _, _ in statSummary = nil; Task { await loadStats() } }

                    if let deadline {
                        Section("請假申請截止日") {
                            Text(deadline).foregroundStyle(.secondary)
                        }
                    }

                    if let statSummary {
                        Section("請假統計") {
                            HStack {
                                Text("總請假節次")
                                Spacer()
                                Text("\(statSummary.sumLeaveSect) 節")
                                    .font(.body.weight(.semibold))
                            }
                            HStack {
                                Text("已核准")
                                Spacer()
                                Text("\(statSummary.sumLeaveSectYes) 節")
                                    .foregroundStyle(.green)
                            }
                            HStack {
                                Text("未核准")
                                Spacer()
                                Text("\(statSummary.sumLeaveSectNo) 節")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }

                    if statSummary?.sumLeaveSect == 0 {
                        Section("請假統計") {
                            Text("尚無請假紀錄").foregroundStyle(.secondary)
                        }
                    } else if !stats.isEmpty {
                        Section("課程明細") {
                            ForEach(stats) { stat in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(alignment: .firstTextBaseline) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(stat.couCna)
                                                .font(.body.weight(.medium))
                                            HStack(spacing: 6) {
                                                if !stat.courseCode.isEmpty {
                                                    Text(stat.courseCode)
                                                }
                                                if let tchCna = stat.tchCna, !tchCna.isEmpty {
                                                    Text(tchCna)
                                                }
                                            }
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text("\(stat.cntLeaveSect) / \(stat.sumSect) 節")
                                                .font(.body.weight(.semibold))
                                            if stat.cntLeaveSectNo > 0 {
                                                Text("未核准 \(stat.cntLeaveSectNo)")
                                                    .font(.caption)
                                                    .foregroundStyle(.orange)
                                            } else if stat.cntLeaveSectYes > 0 {
                                                Text("已核准 \(stat.cntLeaveSectYes)")
                                                    .font(.caption)
                                                    .foregroundStyle(.green)
                                            }
                                        }
                                    }

                                    if !stat.leaveSeqTims.isEmpty {
                                        ForEach(stat.leaveSeqTims) { tim in
                                            HStack(spacing: 6) {
                                                Image(systemName: "calendar")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                Text([tim.displayDate, tim.section].compactMap { $0 }.joined(separator: " "))
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    } else if !stat.seqTims.isEmpty {
                                        Text(stat.seqTims.map(\.displayText).joined(separator: "、"))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable { await loadStats() }
            }
        }
        .task { await loadInitial() }
    }

    private func loadInitial() async {
        isLoading = true
        errorMessage = nil
        async let hyTask      = leaveService.fetchAcademicYears()
        async let deadlineTask = leaveService.fetchApplyDeadline()
        do {
            academicYears = try await hyTask
            selectedHy = academicYears.first
        } catch is CancellationError {
            isLoading = false
            return
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return
        }
        deadline = try? await deadlineTask
        await loadStats()
    }

    private func loadStats() async {
        guard let hy = selectedHy else { return }
        isLoading = statSummary == nil   // only show spinner on first load, not on refresh
        errorMessage = nil
        do {
            let fetched = try await leaveService.fetchLeaveStat(academicYear: hy.hy, semester: selectedHt)
            statSummary = fetched
        } catch is CancellationError {
            // Silently ignore task cancellation (e.g. pull-to-refresh interrupted).
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
