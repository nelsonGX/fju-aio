import SwiftUI

// MARK: - CheckInView

struct CheckInView: View {
    @State private var rollcalls: [Rollcall] = []
    @State private var isLoading = false
    @State private var checkInResults: [Int: RollcallCheckInResult] = [:]
    /// Per-rollcall friend check-in status log (empNo → status)
    @State private var friendCheckInResults: [Int: [String: FriendCheckInStatus]] = [:]
    @State private var manualEntryRollcall: Rollcall? = nil
    @State private var qrScannerRollcall: Rollcall? = nil
    @State private var errorMessage: String? = nil

    // Per-rollcall: credentialed friends in this course
    @State private var rollcallFriends: [Int: [FriendRecord]] = [:]
    // Friends + their pre-authenticated sessions for QR group mode
    @State private var pendingQRFriendSessions: [(FriendRecord, TronClassSession)] = []
    // Friends to include in the next manual number check-in
    @State private var pendingManualFriends: [FriendRecord] = []

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
                    friendResults: friendCheckInResults[rollcall.rollcall_id] ?? [:],
                    proxyFriends: rollcallFriends[rollcall.rollcall_id] ?? [],
                    onManualEntry: { friends in
                        pendingManualFriends = friends
                        manualEntryRollcall = rollcall
                    },
                    onRadarCheckIn: {
                        Task { await doRadarCheckIn(rollcall: rollcall) }
                    },
                    onQRCheckIn: {
                        qrScannerRollcall = rollcall
                    },
                    onProxyRadarCheckIn: { friends in
                        Task { await doRadarCheckIn(rollcall: rollcall, includingFriends: friends) }
                    },
                    onProxyQRCheckin: { sessions in
                        // Sessions are already pre-loaded by RollcallRowView
                        pendingQRFriendSessions = sessions
                        qrScannerRollcall = rollcall
                    },

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
        .sheet(item: $manualEntryRollcall) { rollcall in
            ManualCheckInSheet(rollcall: rollcall) { code in
                manualEntryRollcall = nil
                let friends = pendingManualFriends
                pendingManualFriends = []
                Task { await doManualCheckIn(rollcall: rollcall, code: code, includingFriends: friends.isEmpty ? nil : friends) }
            }
        }
        .sheet(item: $qrScannerRollcall) { rollcall in
            QRScannerSheet(rollcall: rollcall) { qrContent in
                qrScannerRollcall = nil
                let sessions = pendingQRFriendSessions
                pendingQRFriendSessions = []
                Task { await doQRCheckIn(rollcall: rollcall, qrContent: qrContent, friendSessions: sessions) }
            }
        }
    }

    // MARK: - Load

    private func loadRollcalls() async {
        isLoading = true
        defer { isLoading = false }
        print("[CheckIn] Loading active rollcalls...")
        do {
            rollcalls = try await RollcallService.shared.fetchActiveRollcalls()
            print("[CheckIn] Loaded \(rollcalls.count) rollcall(s)")
            await loadFriendsForRollcalls()
        } catch {
            print("[CheckIn] ❌ Failed to load rollcalls: \(error)")
            errorMessage = error.localizedDescription
        }
    }

    /// For each rollcall, fetch the course's student list and intersect with credentialed friends.
    private func loadFriendsForRollcalls() async {
        let credFriends = await MainActor.run { FriendStore.shared.credentialedFriends }
        guard !credFriends.isEmpty else { return }

        await withTaskGroup(of: (Int, [FriendRecord]).self) { group in
            for rollcall in rollcalls {
                let courseCode = rollcall.course_title
                let rid = rollcall.rollcall_id
                group.addTask {
                    let (students, _) = (try? await TronClassAPIService.shared.getEnrollments(courseCode: courseCode)) ?? ([], [:])
                    let classEmpNos = Set(students.map(\.user.user_no))
                    // Only include friends whose student number actually appears in the
                    // course enrollment list — the old condition also tested credEmpNos
                    // which is always true and bypassed the class membership check.
                    let matched = credFriends.filter { classEmpNos.contains($0.empNo) }
                    return (rid, matched)
                }
            }
            for await (rid, friends) in group {
                await MainActor.run { rollcallFriends[rid] = friends }
            }
        }
    }

    // MARK: - Own check-in (+ optional simultaneous friend check-in)

    private func doManualCheckIn(rollcall: Rollcall, code: String, includingFriends: [FriendRecord]?) async {
        print("[CheckIn] Manual check-in: rollcall=\(rollcall.rollcall_id) code=\(code) friends=\(includingFriends?.count ?? 0)")

        if let friends = includingFriends, !friends.isEmpty {
            let skipSelf = rollcall.isAlreadyCheckedIn

            async let selfResult: RollcallCheckInResult = {
                if rollcall.isAlreadyCheckedIn { return .success(code) }
                do {
                    _ = try await RollcallService.shared.manualCheckIn(rollcall: rollcall, code: code)
                    return .success(code)
                } catch {
                    print("[CheckIn] ❌ Self manual check-in error: \(error)")
                    return .failure(error.localizedDescription)
                }
            }()

            async let friendsResult: [String: FriendCheckInStatus] = {
                await withTaskGroup(of: (String, FriendCheckInStatus).self) { group in
                    for friend in friends {
                        let f = friend
                        group.addTask {
                            print("[CheckIn] Authenticating friend \(f.empNo) for manual check-in...")
                            guard let creds = try? CredentialStore.shared.retrieveFriendCredentials(empNo: f.empNo) else {
                                print("[CheckIn] ❌ No credentials for \(f.empNo)")
                                return (f.empNo, .authFailed)
                            }
                            guard let session = try? await GroupRollcallService.shared.authenticateWithCredentials(
                                username: creds.username, password: creds.password
                            ) else {
                                print("[CheckIn] ❌ Auth failed for \(f.empNo)")
                                return (f.empNo, .authFailed)
                            }
                            do {
                                _ = try await GroupRollcallService.shared.manualCheckIn(
                                    rollcall: rollcall, numberCode: code, using: session
                                )
                                print("[CheckIn] Friend \(f.empNo) manual check-in: ✅")
                                return (f.empNo, .success)
                            } catch {
                                print("[CheckIn] Friend \(f.empNo) manual check-in: ❌ \(error)")
                                return (f.empNo, .checkInFailed(error.localizedDescription))
                            }
                        }
                    }
                    var results: [String: FriendCheckInStatus] = [:]
                    for await (empNo, status) in group { results[empNo] = status }
                    return results
                }
            }()

            let (selfCheckInResult, fResults) = await (selfResult, friendsResult)
            let success = isSuccess(selfCheckInResult)
            print("[CheckIn] Manual check-in result: \(success ? "✅" : "❌")")
            if !skipSelf {
                checkInResults[rollcall.rollcall_id] = selfCheckInResult
            }
            friendCheckInResults[rollcall.rollcall_id] = fResults
        } else {
            do {
                let success = try await RollcallService.shared.manualCheckIn(rollcall: rollcall, code: code)
                print("[CheckIn] Manual check-in result: \(success ? "✅" : "❌")")
                checkInResults[rollcall.rollcall_id] = success ? .success(code) : .failure("數字碼錯誤，請再試一次")
            } catch {
                print("[CheckIn] ❌ Manual check-in error: \(error)")
                checkInResults[rollcall.rollcall_id] = .failure(error.localizedDescription)
            }
        }
    }

    private func doRadarCheckIn(rollcall: Rollcall, includingFriends: [FriendRecord]? = nil) async {
        let lat: Double = 25.036238
        let lon: Double = 121.432292
        let acc: Double = 50
        print("[CheckIn] Radar check-in: rollcall=\(rollcall.rollcall_id) friends=\(includingFriends?.count ?? 0)")

        if let friends = includingFriends, !friends.isEmpty {
            // Authenticate all friends first, then fire all check-ins simultaneously
            var friendSessions: [(FriendRecord, TronClassSession)] = []
            var friendResults: [String: FriendCheckInStatus] = [:]
            for friend in friends {
                print("[CheckIn] Authenticating friend \(friend.empNo) for radar...")
                guard let creds = try? CredentialStore.shared.retrieveFriendCredentials(empNo: friend.empNo),
                      let session = try? await GroupRollcallService.shared.authenticateWithCredentials(
                          username: creds.username, password: creds.password
                      ) else {
                    print("[CheckIn] ❌ Auth failed for \(friend.empNo)")
                    friendResults[friend.empNo] = .authFailed
                    continue
                }
                print("[CheckIn] ✅ Auth OK for \(friend.empNo)")
                friendSessions.append((friend, session))
            }

            // Self + friends check-in in parallel
            async let selfResult: RollcallCheckInResult = {
                if rollcall.isAlreadyCheckedIn { return .success(nil) }
                do {
                    _ = try await RollcallService.shared.radarCheckIn(rollcall: rollcall, latitude: lat, longitude: lon, accuracy: acc)
                    return .success(nil)
                } catch {
                    print("[CheckIn] ❌ Self radar error: \(error)")
                    return .failure(error.localizedDescription)
                }
            }()
            let capturedFriendSessions = friendSessions
            async let friendSessionResults: [(String, FriendCheckInStatus)] = {
                await withTaskGroup(of: (String, FriendCheckInStatus).self) { group in
                    for (friend, session) in capturedFriendSessions {
                        let f = friend; let s = session
                        group.addTask {
                            do {
                                _ = try await GroupRollcallService.shared.radarCheckIn(
                                    rollcall: rollcall, latitude: lat, longitude: lon, accuracy: acc, using: s
                                )
                                print("[CheckIn] Friend \(f.empNo) radar: ✅")
                                return (f.empNo, .success)
                            } catch {
                                print("[CheckIn] Friend \(f.empNo) radar: ❌ \(error)")
                                return (f.empNo, .checkInFailed(error.localizedDescription))
                            }
                        }
                    }
                    var out: [(String, FriendCheckInStatus)] = []
                    for await pair in group { out.append(pair) }
                    return out
                }
            }()
            let (selfCheckInResult, sessionResults) = await (selfResult, friendSessionResults)
            let success = isSuccess(selfCheckInResult)
            for (empNo, status) in sessionResults { friendResults[empNo] = status }
            print("[CheckIn] Radar check-in result: \(success ? "✅" : "❌")")
            checkInResults[rollcall.rollcall_id] = selfCheckInResult
            friendCheckInResults[rollcall.rollcall_id] = friendResults
        } else {
            do {
                let success = try await RollcallService.shared.radarCheckIn(rollcall: rollcall, latitude: lat, longitude: lon, accuracy: acc)
                print("[CheckIn] Radar check-in result: \(success ? "✅" : "❌")")
                checkInResults[rollcall.rollcall_id] = success ? .success(nil) : .failure("雷達點名失敗，可能不在教室範圍內")
            } catch {
                print("[CheckIn] ❌ Radar error: \(error)")
                checkInResults[rollcall.rollcall_id] = .failure(error.localizedDescription)
            }
        }
    }

    private func doQRCheckIn(rollcall: Rollcall, qrContent: String, friendSessions: [(FriendRecord, TronClassSession)] = []) async {
        print("[CheckIn] QR check-in: rollcall=\(rollcall.rollcall_id) friends=\(friendSessions.count)")
        if !friendSessions.isEmpty {
            let skipSelf = rollcall.isAlreadyCheckedIn

            async let selfResult: RollcallCheckInResult = {
                if rollcall.isAlreadyCheckedIn { return .success(nil) }
                do {
                    _ = try await RollcallService.shared.qrCheckIn(rollcall: rollcall, qrContent: qrContent)
                    return .success(nil)
                } catch {
                    print("[CheckIn] ❌ Self QR error: \(error)")
                    return .failure(error.localizedDescription)
                }
            }()
            async let friendResults: [String: FriendCheckInStatus] = {
                await withTaskGroup(of: (String, FriendCheckInStatus).self) { group in
                    for (friend, session) in friendSessions {
                        let f = friend; let s = session
                        group.addTask {
                            do {
                                _ = try await GroupRollcallService.shared.qrCheckIn(
                                    rollcall: rollcall, qrContent: qrContent, using: s
                                )
                                print("[CheckIn] Friend \(f.empNo) QR: ✅")
                                return (f.empNo, .success)
                            } catch {
                                print("[CheckIn] Friend \(f.empNo) QR: ❌ \(error)")
                                return (f.empNo, .checkInFailed(error.localizedDescription))
                            }
                        }
                    }
                    var results: [String: FriendCheckInStatus] = [:]
                    for await (empNo, status) in group { results[empNo] = status }
                    return results
                }
            }()
            let (selfCheckInResult, fResults) = await (selfResult, friendResults)
            let success = isSuccess(selfCheckInResult)
            print("[CheckIn] QR check-in result: \(success ? "✅" : "❌")")
            if !skipSelf {
                checkInResults[rollcall.rollcall_id] = selfCheckInResult
            }
            friendCheckInResults[rollcall.rollcall_id] = fResults
        } else {
            do {
                let success = try await RollcallService.shared.qrCheckIn(rollcall: rollcall, qrContent: qrContent)
                print("[CheckIn] QR check-in result: \(success ? "✅" : "❌")")
                checkInResults[rollcall.rollcall_id] = success ? .success(nil) : .failure("QR Code 點名失敗，請再試一次")
            } catch {
                print("[CheckIn] ❌ QR error: \(error)")
                checkInResults[rollcall.rollcall_id] = .failure(error.localizedDescription)
            }
        }
    }

    private func isSuccess(_ result: RollcallCheckInResult) -> Bool {
        if case .success = result { return true }
        return false
    }
}

// MARK: - Rollcall Row

struct RollcallRowView: View {
    let rollcall: Rollcall
    let result: RollcallCheckInResult?
    /// Per-friend check-in statuses returned after a group check-in (empNo → status)
    let friendResults: [String: FriendCheckInStatus]
    let proxyFriends: [FriendRecord]
    /// Called when user wants to enter a number code; passes selected proxy friends (empty if group mode off)
    let onManualEntry: ([FriendRecord]) -> Void
    let onRadarCheckIn: () -> Void
    let onQRCheckIn: () -> Void
    /// Called when group mode is on and user taps radar check-in (friends list)
    let onProxyRadarCheckIn: ([FriendRecord]) -> Void
    /// Called when group mode is on and user taps QR check-in (passes pre-loaded sessions)
    let onProxyQRCheckin: ([(FriendRecord, TronClassSession)]) -> Void

    /// Group rollcall toggle state
    @State private var groupModeEnabled = false
    /// Which friends are currently selected (default: all)
    @State private var selectedFriendIds: Set<String> = []
    /// Pre-authenticated friend sessions for QR/radar check-in
    @State private var friendSessions: [String: TronClassSession] = [:]
    @State private var isPreloadingSessions = false

    /// Computed: friends currently selected
    private var selectedFriends: [FriendRecord] {
        proxyFriends.filter { selectedFriendIds.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            let canCheckInForFriends = groupModeEnabled && !selectedFriends.isEmpty

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

            // Own check-in button / result. If self is already checked in, keep
            // the action available only for selected proxy friends.
            if rollcall.isActive {
                if let result, !canCheckInForFriends {
                    resultView(result)
                } else if !rollcall.isAlreadyCheckedIn || canCheckInForFriends {
                    if rollcall.isNumber {
                        Button(action: {
                            // Pass selected friends; empty if group mode is off
                            onManualEntry(groupModeEnabled ? selectedFriends : [])
                        }) {
                            Label("輸入數字碼", systemImage: "keyboard").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).tint(AppTheme.accent)
                    } else if rollcall.isQR {
                        Button(action: {
                            if groupModeEnabled && !selectedFriends.isEmpty {
                                // Pass pre-loaded sessions so the QR content can be sent immediately after scan
                                let sessions = selectedFriends.compactMap { f -> (FriendRecord, TronClassSession)? in
                                    guard let s = friendSessions[f.id] else { return nil }
                                    return (f, s)
                                }
                                if !sessions.isEmpty {
                                    onProxyQRCheckin(sessions)
                                } else if !rollcall.isAlreadyCheckedIn {
                                    onQRCheckIn()
                                }
                            } else {
                                onQRCheckIn()
                            }
                        }) {
                            Label("掃描 QR Code", systemImage: "qrcode.viewfinder").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).tint(AppTheme.accent)
                        .disabled(
                            groupModeEnabled &&
                            (isPreloadingSessions || (rollcall.isAlreadyCheckedIn && selectedFriends.allSatisfy { friendSessions[$0.id] == nil }))
                        )
                        .overlay(alignment: .trailing) {
                            if groupModeEnabled && isPreloadingSessions {
                                ProgressView().controlSize(.small).padding(.trailing, 12)
                            }
                        }
                    } else if rollcall.isRadar {
                        Button(action: {
                            if groupModeEnabled && !selectedFriends.isEmpty {
                                onProxyRadarCheckIn(selectedFriends)
                            } else {
                                onRadarCheckIn()
                            }
                        }) {
                            Label("雷達簽到", systemImage: "location.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).tint(.blue)
                    }
                } else {
                    Label("你已完成簽到", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                }
            } else if rollcall.isActive && rollcall.isAlreadyCheckedIn && groupModeEnabled && !selectedFriends.isEmpty {
                // Self already checked in — show proxy-only check-in buttons for friends
                if rollcall.isNumber {
                    Button(action: { onManualEntry(selectedFriends) }) {
                        Label("為朋友輸入數字碼", systemImage: "keyboard").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(AppTheme.accent)
                } else if rollcall.isQR {
                    Button(action: {
                        let sessions = selectedFriends.compactMap { f -> (FriendRecord, TronClassSession)? in
                            guard let s = friendSessions[f.id] else { return nil }
                            return (f, s)
                        }
                        onProxyQRCheckin(sessions)
                    }) {
                        Label("為朋友掃描 QR Code", systemImage: "qrcode.viewfinder").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(AppTheme.accent)
                    .disabled(isPreloadingSessions)
                    .overlay(alignment: .trailing) {
                        if isPreloadingSessions {
                            ProgressView().controlSize(.small).padding(.trailing, 12)
                        }
                    }
                } else if rollcall.isRadar {
                    Button(action: { onProxyRadarCheckIn(selectedFriends) }) {
                        Label("為朋友雷達簽到", systemImage: "location.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(.blue)
                }
            }

            // Friend check-in status log (shown after a group check-in completes)
            if !friendResults.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("朋友簽到結果").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(proxyFriends.filter { friendResults[$0.empNo] != nil }) { friend in
                        HStack(spacing: 8) {
                            friendStatusIcon(friendResults[friend.empNo]!)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(friend.displayName).font(.caption)
                                if case .checkInFailed(let msg) = friendResults[friend.empNo]! {
                                    Text(msg).font(.caption2).foregroundStyle(.secondary)
                                } else if case .authFailed = friendResults[friend.empNo]! {
                                    Text("帳號登入失敗").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            // Group rollcall section (only if there are credentialed friends)
            if !proxyFriends.isEmpty && rollcall.isActive {
                Divider()

                // Toggle row
                HStack {
                    Image(systemName: "person.2.fill").font(.caption)
                    Text("代替朋友同時點名").font(.caption.weight(.medium))
                    Spacer()
                    Toggle("", isOn: $groupModeEnabled)
                        .labelsHidden()
                        .tint(AppTheme.accent)
                        .onChange(of: groupModeEnabled) { _, enabled in
                            if enabled {
                                // Default: select all friends
                                selectedFriendIds = Set(proxyFriends.map(\.id))
                                // For radar/QR: pre-load sessions to avoid QR timeout
                                if rollcall.isRadar || rollcall.isQR {
                                    Task { await preloadFriendSessions() }
                                }
                            } else {
                                selectedFriendIds = []
                                friendSessions = [:]
                            }
                        }
                }
                .foregroundStyle(AppTheme.accent)

                // Friend list (only shown when toggle is on)
                if groupModeEnabled {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(proxyFriends) { friend in
                            HStack(spacing: 10) {
                                Button {
                                    if selectedFriendIds.contains(friend.id) {
                                        selectedFriendIds.remove(friend.id)
                                    } else {
                                        selectedFriendIds.insert(friend.id)
                                        // Load session for this friend if needed
                                        if (rollcall.isRadar || rollcall.isQR) && friendSessions[friend.id] == nil {
                                            Task { await preloadFriendSession(friend) }
                                        }
                                    }
                                } label: {
                                    Image(systemName: selectedFriendIds.contains(friend.id)
                                          ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedFriendIds.contains(friend.id)
                                                         ? AppTheme.accent : .secondary)
                                }
                                .buttonStyle(.plain)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(friend.displayName).font(.subheadline)
                                    Text(friend.empNo).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()

                                // Session pre-load indicator (for radar/QR)
                                if (rollcall.isRadar || rollcall.isQR) && selectedFriendIds.contains(friend.id) {
                                    if friendSessions[friend.id] != nil {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.caption)
                                            .foregroundStyle(.green)
                                    } else if isPreloadingSessions {
                                        ProgressView().controlSize(.mini)
                                    }
                                }
                            }
                        }

                        if rollcall.isRadar || rollcall.isQR {
                            let readyCount = selectedFriends.filter { friendSessions[$0.id] != nil }.count
                            let totalSelected = selectedFriends.count
                            if isPreloadingSessions {
                                Label("正在登入朋友的帳號... (\(readyCount)/\(totalSelected))", systemImage: "arrow.clockwise")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            } else if readyCount < totalSelected && totalSelected > 0 {
                                Label("部分帳號登入失敗（\(totalSelected - readyCount) 人）", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    // MARK: - Session Pre-loading

    private func preloadFriendSessions() async {
        isPreloadingSessions = true
        defer { isPreloadingSessions = false }

        await withTaskGroup(of: (String, TronClassSession?).self) { group in
            for friend in proxyFriends {
                let f = friend
                group.addTask {
                    guard let creds = try? CredentialStore.shared.retrieveFriendCredentials(empNo: f.empNo) else {
                        return (f.id, nil)
                    }
                    let session = try? await GroupRollcallService.shared.authenticateWithCredentials(
                        username: creds.username, password: creds.password
                    )
                    return (f.id, session)
                }
            }
            for await (id, session) in group {
                if let session {
                    friendSessions[id] = session
                }
            }
        }
    }

    private func preloadFriendSession(_ friend: FriendRecord) async {
        guard let creds = try? CredentialStore.shared.retrieveFriendCredentials(empNo: friend.empNo) else { return }
        if let session = try? await GroupRollcallService.shared.authenticateWithCredentials(
            username: creds.username, password: creds.password
        ) {
            friendSessions[friend.id] = session
        }
    }

    @ViewBuilder
    private func friendStatusIcon(_ status: FriendCheckInStatus) -> some View {
        switch status {
        case .success:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
        case .authFailed:
            Image(systemName: "lock.fill").foregroundStyle(.orange).font(.caption)
        case .notEnrolled:
            Image(systemName: "person.fill.xmark").foregroundStyle(.orange).font(.caption)
        case .checkInFailed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red).font(.caption)
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
