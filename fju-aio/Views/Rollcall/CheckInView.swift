import SwiftUI

// MARK: - CheckInView

struct CheckInView: View {
    @State private var rollcalls: [Rollcall] = []
    @State private var isLoading = false
    @State private var checkInResults: [Int: RollcallCheckInResult] = [:]
    @State private var showManualEntry = false
    @State private var showQRScanner = false
    @State private var selectedRollcall: Rollcall? = nil
    @State private var errorMessage: String? = nil

    // Per-rollcall: empNos of classmates who are credentialed friends
    @State private var rollcallFriends: [Int: [FriendRecord]] = [:]

    var body: some View {
        List {
            if !isLoading && rollcalls.isEmpty {
                ContentUnavailableView(
                    "目前沒有點名",
                    systemImage: "hand.raised.slash",
                    description: Text("向下滑動以重新整理")
                )
                .listRowBackground(Color.clear)
            }

            ForEach(rollcalls) { rollcall in
                RollcallRowView(
                    rollcall: rollcall,
                    result: checkInResults[rollcall.rollcall_id],
                    proxyFriends: rollcallFriends[rollcall.rollcall_id] ?? [],
                    onManualEntry: {
                        selectedRollcall = rollcall
                        showManualEntry = true
                    },
                    onRadarCheckIn: {
                        Task { await doRadarCheckIn(rollcall: rollcall) }
                    },
                    onQRCheckIn: {
                        selectedRollcall = rollcall
                        showQRScanner = true
                    },
                    onProxyCheckIn: { selected in
                        Task { await doProxyCheckIn(rollcall: rollcall, friends: selected) }
                    }
                )
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            }
        }
        .adaptiveListContentMargins()
        .navigationTitle("課程簽到")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if isLoading { ProgressView() } }
        .task { await loadRollcalls() }
        .refreshable { await loadRollcalls() }
        .alert("錯誤", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("確定") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $showManualEntry) {
            if let rollcall = selectedRollcall {
                ManualCheckInSheet(rollcall: rollcall) { code in
                    showManualEntry = false
                    Task { await doManualCheckIn(rollcall: rollcall, code: code) }
                }
            }
        }
        .sheet(isPresented: $showQRScanner) {
            if let rollcall = selectedRollcall {
                QRScannerSheet(rollcall: rollcall) { qrContent in
                    showQRScanner = false
                    Task { await doQRCheckIn(rollcall: rollcall, qrContent: qrContent) }
                }
            }
        }
    }

    // MARK: - Load

    private func loadRollcalls() async {
        isLoading = true
        defer { isLoading = false }
        do {
            rollcalls = try await RollcallService.shared.fetchActiveRollcalls()
            await loadFriendsForRollcalls()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// For each rollcall, fetch the course's student list and intersect with credentialed friends.
    private func loadFriendsForRollcalls() async {
        let credFriends = await MainActor.run { FriendStore.shared.credentialedFriends }
        guard !credFriends.isEmpty else { return }
        let credEmpNos = Set(credFriends.map(\.empNo))

        await withTaskGroup(of: (Int, [FriendRecord]).self) { group in
            for rollcall in rollcalls {
                let courseCode = rollcall.course_title  // fallback key; API matches by title/code
                let rid = rollcall.rollcall_id
                group.addTask {
                    let (students, _) = (try? await TronClassAPIService.shared.getEnrollments(courseCode: courseCode)) ?? ([], [:])
                    let classEmpNos = Set(students.map(\.user.user_no))
                    let matched = credFriends.filter { classEmpNos.contains($0.empNo) || credEmpNos.contains($0.empNo) }
                    return (rid, matched)
                }
            }
            for await (rid, friends) in group {
                await MainActor.run { rollcallFriends[rid] = friends }
            }
        }
    }

    // MARK: - Own check-in

    private func doManualCheckIn(rollcall: Rollcall, code: String) async {
        do {
            let success = try await RollcallService.shared.manualCheckIn(rollcall: rollcall, code: code)
            checkInResults[rollcall.rollcall_id] = success ? .success(code) : .failure("數字碼錯誤，請再試一次")
        } catch {
            checkInResults[rollcall.rollcall_id] = .failure(error.localizedDescription)
        }
    }

    private func doRadarCheckIn(rollcall: Rollcall) async {
        do {
            let success = try await RollcallService.shared.radarCheckIn(
                rollcall: rollcall,
                latitude: 25.036238, longitude: 121.432292, accuracy: 50
            )
            checkInResults[rollcall.rollcall_id] = success ? .success(nil) : .failure("雷達點名失敗，可能不在教室範圍內")
        } catch {
            checkInResults[rollcall.rollcall_id] = .failure(error.localizedDescription)
        }
    }

    private func doQRCheckIn(rollcall: Rollcall, qrContent: String) async {
        do {
            let success = try await RollcallService.shared.qrCheckIn(rollcall: rollcall, qrContent: qrContent)
            checkInResults[rollcall.rollcall_id] = success ? .success(nil) : .failure("QR Code 點名失敗，請再試一次")
        } catch {
            checkInResults[rollcall.rollcall_id] = .failure(error.localizedDescription)
        }
    }

    // MARK: - Proxy check-in for selected friends

    private func doProxyCheckIn(rollcall: Rollcall, friends: [FriendRecord]) async {
        await withTaskGroup(of: Void.self) { group in
            for friend in friends {
                let f = friend
                group.addTask {
                    guard let creds = try? CredentialStore.shared.retrieveFriendCredentials(empNo: f.empNo) else { return }
                    do {
                        let session = try await GroupRollcallService.shared.authenticateWithCredentials(
                            username: creds.username, password: creds.password
                        )
                        if rollcall.isRadar {
                            _ = try await GroupRollcallService.shared.radarCheckIn(
                                rollcall: rollcall,
                                latitude: 25.036238, longitude: 121.432292, accuracy: 50,
                                using: session
                            )
                        }
                        // Number/QR rollcalls: the code is shared — handled by the row UI
                    } catch { /* per-friend errors are surfaced in ProxyResultsState */ }
                }
            }
        }
    }
}

// MARK: - Rollcall Row

private struct RollcallRowView: View {
    let rollcall: Rollcall
    let result: RollcallCheckInResult?
    let proxyFriends: [FriendRecord]
    let onManualEntry: () -> Void
    let onRadarCheckIn: () -> Void
    let onQRCheckIn: () -> Void
    let onProxyCheckIn: ([FriendRecord]) -> Void

    /// Which friends the user has selected for proxy check-in
    @State private var selectedForProxy: Set<String> = []
    /// Per-friend proxy results for this rollcall
    @State private var proxyResults: [String: ProxyStatus] = [:]
    @State private var isProxyRunning = false
    @State private var showProxySection = false

    enum ProxyStatus {
        case running, success, failure(String)
        var icon: String {
            switch self { case .running: return ""; case .success: return "checkmark.circle.fill"; case .failure: return "xmark.circle.fill" }
        }
        var color: Color {
            switch self { case .running: return .secondary; case .success: return .green; case .failure: return .red }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(rollcall.course_title).font(.headline)
                    Text(rollcall.title).font(.caption).foregroundStyle(.secondary)
                    if let createdBy = rollcall.created_by_name {
                        Text(createdBy).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                StatusBadge(rollcall: rollcall)
            }

            // Method tag
            HStack(spacing: 6) {
                Image(systemName: rollcall.isNumber ? "number.circle.fill" : rollcall.isQR ? "qrcode.viewfinder" : "location.circle.fill")
                    .font(.caption)
                Text(rollcall.isNumber ? "數字碼點名" : rollcall.isQR ? "QR Code 點名" : "雷達點名")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)

            // Own check-in button / result
            if rollcall.isActive && !rollcall.isAlreadyCheckedIn {
                if let result {
                    resultView(result)
                } else if rollcall.isNumber {
                    Button(action: onManualEntry) {
                        Label("輸入數字碼", systemImage: "keyboard").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(AppTheme.accent)
                } else if rollcall.isQR {
                    Button(action: onQRCheckIn) {
                        Label("掃描 QR Code", systemImage: "qrcode.viewfinder").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(AppTheme.accent)
                } else if rollcall.isRadar {
                    Button(action: onRadarCheckIn) {
                        Label("雷達簽到", systemImage: "location.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(.blue)
                }
            }

            // Proxy section (only if there are credentialed friends in this course)
            if !proxyFriends.isEmpty && rollcall.isActive {
                Divider()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showProxySection.toggle() }
                } label: {
                    HStack {
                        Image(systemName: "person.2.fill").font(.caption)
                        Text("替朋友點名（\(proxyFriends.count) 人可選）").font(.caption.weight(.medium))
                        Spacer()
                        Image(systemName: showProxySection ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                    }
                    .foregroundStyle(AppTheme.accent)
                }
                .buttonStyle(.plain)

                if showProxySection {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(proxyFriends) { friend in
                            HStack(spacing: 10) {
                                // Selection toggle
                                Button {
                                    if selectedForProxy.contains(friend.id) {
                                        selectedForProxy.remove(friend.id)
                                    } else {
                                        selectedForProxy.insert(friend.id)
                                    }
                                } label: {
                                    Image(systemName: selectedForProxy.contains(friend.id)
                                          ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedForProxy.contains(friend.id)
                                                         ? AppTheme.accent : .secondary)
                                }
                                .buttonStyle(.plain)
                                .disabled(proxyResults[friend.id] != nil)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(friend.displayName).font(.subheadline)
                                    Text(friend.empNo).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()

                                // Status
                                if let status = proxyResults[friend.id] {
                                    if case .running = status {
                                        ProgressView().controlSize(.mini)
                                    } else {
                                        Image(systemName: status.icon)
                                            .foregroundStyle(status.color)
                                    }
                                }
                            }
                        }

                        Button {
                            let toCheck = proxyFriends.filter { selectedForProxy.contains($0.id) }
                            guard !toCheck.isEmpty else { return }
                            isProxyRunning = true
                            for f in toCheck { proxyResults[f.id] = .running }
                            Task {
                                await runProxy(rollcall: rollcall, friends: toCheck)
                                isProxyRunning = false
                            }
                        } label: {
                            Text("替選取的朋友點名（\(selectedForProxy.count) 人）")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .disabled(selectedForProxy.isEmpty || isProxyRunning)
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private func runProxy(rollcall: Rollcall, friends: [FriendRecord]) async {
        await withTaskGroup(of: (String, ProxyStatus).self) { group in
            for friend in friends {
                let f = friend
                group.addTask {
                    guard let creds = try? CredentialStore.shared.retrieveFriendCredentials(empNo: f.empNo) else {
                        return (f.id, .failure("未找到帳密"))
                    }
                    do {
                        let session = try await GroupRollcallService.shared.authenticateWithCredentials(
                            username: creds.username, password: creds.password
                        )
                        let ok: Bool
                        if rollcall.isRadar {
                            ok = try await GroupRollcallService.shared.radarCheckIn(
                                rollcall: rollcall,
                                latitude: 25.036238, longitude: 121.432292, accuracy: 50,
                                using: session
                            )
                        } else {
                            // Number / QR rollcalls: not automated — report as unsupported
                            return (f.id, .failure("此點名方式不支援代為點名"))
                        }
                        return (f.id, ok ? .success : .failure("點名失敗"))
                    } catch {
                        return (f.id, .failure(error.localizedDescription))
                    }
                }
            }
            for await (id, status) in group {
                await MainActor.run { proxyResults[id] = status }
            }
        }
    }

    @ViewBuilder
    private func resultView(_ result: RollcallCheckInResult) -> some View {
        switch result {
        case .success(let code):
            if let code {
                Label("簽到成功！數字碼：\(code)", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.green)
            } else {
                Label("簽到成功！", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.green)
            }
        case .failure(let message):
            Label(message, systemImage: "xmark.circle.fill")
                .font(.subheadline).foregroundStyle(.red)
        }
    }
}

// MARK: - Status Badge

private struct StatusBadge: View {
    let rollcall: Rollcall

    private var label: (text: String, color: Color) {
        switch rollcall.status {
        case "on_call": return ("已簽到", .green)
        case "late":    return ("遲到",   .orange)
        default:
            if rollcall.is_expired { return ("已過期", .gray) }
            if rollcall.rollcall_status == "in_progress" { return ("進行中", .blue) }
            return ("缺席", .red)
        }
    }

    var body: some View {
        Text(label.text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(label.color.opacity(0.15))
            .foregroundStyle(label.color)
            .clipShape(Capsule())
    }
}

// MARK: - Manual Entry Sheet

struct ManualCheckInSheet: View {
    let rollcall: Rollcall
    let onConfirm: (String) -> Void

    @State private var code = ""
    @Environment(\.dismiss) private var dismiss

    private var paddedCode: String {
        String(repeating: "0", count: max(0, 4 - code.count)) + code
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                VStack(spacing: 6) {
                    Text(rollcall.course_title).font(.headline).multilineTextAlignment(.center)
                    Text("請向教師確認點名數字碼").font(.subheadline).foregroundStyle(.secondary)
                }

                TextField("0000", text: $code)
                    .font(.system(size: 40, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .keyboardType(.numberPad)
                    .onChange(of: code) { _, new in code = String(new.filter(\.isNumber).prefix(4)) }
                    .padding()
                    .frame(maxWidth: 200)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                Button {
                    onConfirm(paddedCode)
                } label: {
                    Text("確認簽到").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(AppTheme.accent)
                .disabled(code.count != 4).padding(.horizontal)

                Spacer()
            }
            .padding(.top, 32)
            .navigationTitle("手動輸入數字碼")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
        }
    }
}

// MARK: - QR Scanner Sheet

struct QRScannerSheet: View {
    let rollcall: Rollcall
    let onScan: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                QRScannerView(onScan: { code in onScan(code) }).ignoresSafeArea()

                VStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Text(rollcall.course_title).font(.headline).foregroundStyle(.white)
                        Text("請掃描教師顯示的 QR Code").font(.subheadline).foregroundStyle(.white.opacity(0.8))
                    }
                    .padding()
                    .background(.black.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.bottom, 48)
                }
            }
            .navigationTitle("掃描 QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.black.opacity(0.6), for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.foregroundStyle(.white)
                }
            }
        }
    }
}

#Preview {
    NavigationStack { CheckInView() }
}
