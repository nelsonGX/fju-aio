import SwiftUI

// MARK: - FriendListView
// Entry is gated: user must have published their profile first.

struct FriendListView: View {
    @AppStorage("myProfile.isPublished") private var isPublished = false

    var body: some View {
        if isPublished {
            FriendListContent()
        } else {
            ProfileRequiredView()
        }
    }
}

// MARK: - Profile Required Prompt

private struct ProfileRequiredView: View {
    var body: some View {
        ContentUnavailableView {
            Label("尚未建立公開資料", systemImage: "person.crop.circle.badge.exclamationmark")
        } description: {
            Text("必須先發布你的公開資料，才能新增好友或被好友找到。")
        } actions: {
            NavigationLink(destination: MyProfileView()) {
                Text("前往建立資料")
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
        }
        .navigationTitle("好友")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Friend List Content

private struct FriendListContent: View {
    @Environment(AuthenticationManager.self) private var authManager
    @State private var friendStore = FriendStore.shared
    @State private var showAddFriend = false
    @State private var nearbyService = NearbyFriendService.shared
    @State private var scanError: String?
    @State private var lastScannedInfo: String?
    @State private var sisSession: SISSession?
    @State private var isLoadingSession = false
    @State private var sessionError: String?
    @AppStorage("friendList.shareCredentialQRCode") private var shareCredentialQRCode = false

    var body: some View {
        List {
            // MARK: 你的朋友
            Section("你的朋友") {
                if friendStore.friends.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "person.2.slash")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text("點右上角加號來新增好友")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 12)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(friendStore.friends) { friend in
                        NavigationLink {
                            FriendDetailView(friend: friend)
                        } label: {
                            FriendRow(friend: friend)
                        }
                    }
                    .onDelete { offsets in
                        offsets.forEach { friendStore.removeFriend(id: friendStore.friends[$0].id) }
                    }
                }
            }
        }
        .navigationTitle("好友")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        if sisSession == nil {
                            await loadSession(force: true)
                        }
                        showAddFriend = true
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("掃描結果", isPresented: Binding(
            get: { scanError != nil || lastScannedInfo != nil },
            set: { if !$0 { scanError = nil; lastScannedInfo = nil } }
        )) {
            Button("確定") { scanError = nil; lastScannedInfo = nil }
        } message: {
            Text(scanError ?? lastScannedInfo ?? "")
        }
        .sheet(isPresented: $showAddFriend) {
            AddFriendSheet(
                session: sisSession,
                sharesCredentials: $shareCredentialQRCode,
                isLoadingSession: isLoadingSession,
                sessionError: sessionError,
                onRetrySession: { Task { await loadSession(force: true) } },
                onScannedQRCode: { qrString in
                    handleScanned(qrString)
                },
                onRequestAddPeer: { peer in
                    addFriend(peer)
                    nearbyService.sendAddRequest(to: peer)
                },
                onAcceptIncomingPeer: { peer in
                    addFriend(peer)
                }
            )
        }
        .task { await loadSession() }
        .refreshable { await refreshAll() }
    }

    @MainActor
    private func refreshAll() async {
        await loadSession(force: true)
        // Re-fetch CloudKit profiles for all friends to get latest data
        await withTaskGroup(of: Void.self) { group in
            for friend in friendStore.friends {
                group.addTask {
                    if let profile = try? await CloudKitProfileService.shared.fetchProfile(recordName: friend.id) {
                        await MainActor.run {
                            self.friendStore.updateCachedProfile(profile, for: friend.id)
                        }
                    }
                }
            }
        }
    }

    @MainActor
    private func loadSession(force: Bool = false) async {
        if sisSession != nil, !force { return }
        isLoadingSession = true
        sessionError = nil
        defer { isLoadingSession = false }
        do {
            sisSession = try await authManager.getValidSISSession()
        } catch {
            sisSession = nil
            sessionError = "無法載入學校帳號資料，請確認已登入後再試一次。"
        }
    }

    private func handleScanned(_ qrString: String) {
        let myToken = ProfileQRService.stableDeviceToken()
        switch ProfileQRService.parse(qrString: qrString) {
        case .profile(let payload):
            if payload.cloudKitRecordName == myToken {
                scanError = "這是你自己的 QR Code，無法加自己為好友。"
                return
            }
            guard !friendStore.isFriend(recordName: payload.cloudKitRecordName) else {
                lastScannedInfo = "\(payload.displayName) 已經在好友列表中。"
                return
            }
            friendStore.addFriend(from: payload)
            lastScannedInfo = "已新增好友：\(payload.displayName)（\(payload.empNo)）"
            fetchAndCacheProfile(recordName: payload.cloudKitRecordName)
        case .mutual(let payload):
            if payload.cloudKitRecordName == myToken {
                scanError = "這是你自己的 QR Code，無法加自己為好友。"
                return
            }
            guard !friendStore.isFriend(recordName: payload.cloudKitRecordName) else {
                lastScannedInfo = "\(payload.displayName) 已經在好友列表中。"
                return
            }
            let profilePayload = ProfileQRPayload(
                version: payload.version,
                type: "profile",
                cloudKitRecordName: payload.cloudKitRecordName,
                empNo: payload.empNo,
                displayName: payload.displayName,
                userId: payload.userId
            )
            friendStore.addFriend(from: profilePayload)
            lastScannedInfo = "已新增好友：\(payload.displayName)（\(payload.empNo)）"
            fetchAndCacheProfile(recordName: payload.cloudKitRecordName)
            startNearbyIfPossible()
            nearbyService.sendAddRequest(to: payload)
        case .combined(let payload):
            if payload.cloudKitRecordName == myToken {
                scanError = "這是你自己的 QR Code，無法加自己為好友。"
                return
            }
            let wasAlreadyFriend = friendStore.isFriend(recordName: payload.cloudKitRecordName)
            let profilePayload = ProfileQRPayload(
                version: payload.version,
                type: "profile",
                cloudKitRecordName: payload.cloudKitRecordName,
                empNo: payload.empNo,
                displayName: payload.displayName,
                userId: payload.userId
            )
            if !wasAlreadyFriend {
                friendStore.addFriend(from: profilePayload)
            }
            if let friendId = friendStore.friends.first(where: { $0.id == payload.cloudKitRecordName })?.id {
                friendStore.saveCredentials(for: friendId, username: payload.username, password: payload.password)
            }
            lastScannedInfo = wasAlreadyFriend
                ? "已更新 \(payload.displayName) 的點名授權"
                : "已新增好友：\(payload.displayName)（\(payload.empNo)）並儲存點名授權"
            fetchAndCacheProfile(recordName: payload.cloudKitRecordName)
        case .groupRollcall:
            scanError = "這是點名 QR Code，請在簽到頁面使用。"
        case .unknown:
            scanError = "無法識別此 QR Code。"
        }
    }

    private func fetchAndCacheProfile(recordName: String) {
        Task {
            if let profile = try? await CloudKitProfileService.shared.fetchProfile(recordName: recordName) {
                await MainActor.run {
                    friendStore.updateCachedProfile(profile, for: recordName)
                }
            }
        }
    }

    private func addFriend(_ peer: NearbyPeerProfile) {
        guard !friendStore.isFriend(recordName: peer.id) else { return }
        let payload = ProfileQRPayload(
            version: 1,
            type: "profile",
            cloudKitRecordName: peer.id,
            empNo: peer.empNo,
            displayName: peer.displayName,
            userId: peer.userId
        )
        friendStore.addFriend(from: payload)
        fetchAndCacheProfile(recordName: peer.id)
    }

    private func startNearbyIfPossible() {
        guard let sisSession else { return }
        let myPayload = ProfileQRService.makeMutualPayload(
            userId: sisSession.userId,
            empNo: sisSession.empNo,
            displayName: sisSession.userName
        )
        nearbyService.start(profile: myPayload)
    }
}

// MARK: - Add Friend Sheet

private struct AddFriendSheet: View {
    let session: SISSession?
    @Binding var sharesCredentials: Bool
    let isLoadingSession: Bool
    let sessionError: String?
    let onRetrySession: () -> Void
    let onScannedQRCode: (String) -> Void
    let onRequestAddPeer: (NearbyPeerProfile) -> Void
    let onAcceptIncomingPeer: (NearbyPeerProfile) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var nearbyService = NearbyFriendService.shared
    @State private var friendStore = FriendStore.shared
    @State private var showScanner = false
    @State private var addedIds: Set<String> = []
    @State private var nearbyStartNonce = UUID()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    myQRCodeView

                    Toggle(isOn: $sharesCredentials) {
                        Label("包含點名授權", systemImage: "person.badge.key.fill")
                    }
                    .foregroundStyle(sharesCredentials ? .orange : .primary)

                    if sharesCredentials {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("這個 QR Code 含有帳號密碼。分享後對方可以替你點名，請勿任意外流。")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("我的 QR Code")
                } footer: {
                    Text("讓朋友掃描這個 QR Code 來加你為好友。")
                }

                Section {
                    Button {
                        showScanner = true
                    } label: {
                        AddFriendActionRow(
                            icon: "qrcode.viewfinder",
                            tint: AppTheme.accent,
                            title: "掃描 QR Code",
                            subtitle: "掃描朋友的個人 QR Code 來新增好友"
                        )
                    }
                    .buttonStyle(.plain)
                }

                Section {
                    nearbyStatusRow
                    Text("使用附近加好友時，請把兩台手機靠近並保持這個畫面開啟，距離太遠時可能會搜尋到但連線失敗。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("附近加好友")
                }

                if !incomingRequests.isEmpty {
                    Section("邀請") {
                        ForEach(incomingRequests) { peer in
                            incomingRequestRow(peer)
                        }
                    }
                }

                if !pendingPeers.isEmpty {
                    Section("附近的人") {
                        ForEach(pendingPeers) { peer in
                            peerRow(peer, isAdded: false)
                        }
                    }
                }

                if !addedPeers.isEmpty {
                    Section("已新增") {
                        ForEach(addedPeers) { peer in
                            peerRow(peer, isAdded: true)
                        }
                    }
                }

                if nearbyService.isActive && incomingRequests.isEmpty && pendingPeers.isEmpty && addedPeers.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label("尚未找到附近的人", systemImage: "person.2.slash")
                        } description: {
                            Text("請確認對方也開啟加好友頁面，並把兩台手機靠近一點。")
                        } actions: {
                            Button("重新搜尋") {
                                restartNearby()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("新增好友")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") {
                        nearbyService.stop()
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showScanner) {
            FriendQRScannerSheet { qrString in
                showScanner = false
                onScannedQRCode(qrString)
            }
        }
        .task(id: startTaskID) {
            startNearby()
        }
        .onAppear {
            startNearby()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                startNearby()
            }
        }
        .onDisappear {
            nearbyService.stop()
        }
    }

    private var incomingRequests: [NearbyPeerProfile] {
        nearbyService.incomingAddRequests.filter { !friendStore.isFriend(recordName: $0.id) }
    }

    private var visiblePeers: [NearbyPeerProfile] {
        nearbyService.discoveredPeers.filter { !friendStore.isFriend(recordName: $0.id) }
    }

    private var pendingPeers: [NearbyPeerProfile] {
        visiblePeers.filter { !addedIds.contains($0.id) }
    }

    private var addedPeers: [NearbyPeerProfile] {
        visiblePeers.filter { addedIds.contains($0.id) }
    }

    private var startTaskID: String {
        "\(session?.empNo ?? "no-session")-\(nearbyStartNonce.uuidString)"
    }

    @ViewBuilder
    private var myQRCodeView: some View {
        VStack(spacing: 12) {
            if let session, let image = makeQRImage(session: session) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 220, height: 220)
                    .padding()
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                VStack(spacing: 3) {
                    Text(session.userName)
                        .font(.headline)
                    Text(session.empNo)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if isLoadingSession {
                ProgressView("載入中...")
                    .frame(maxWidth: .infinity)
                    .frame(height: 260)
            } else {
                ContentUnavailableView {
                    Label("無法顯示 QR Code", systemImage: "qrcode")
                } description: {
                    Text(qrUnavailableMessage)
                } actions: {
                    Button("重試", action: onRetrySession)
                        .buttonStyle(.borderedProminent)
                }
                .frame(minHeight: 220)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var nearbyStatusRow: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(nearbyService.isActive ? Color.green.opacity(0.15) : Color.secondary.opacity(0.12))
                    .frame(width: 42, height: 42)
                Image(systemName: nearbyService.isActive ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                    .foregroundStyle(nearbyService.isActive ? .green : .secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(nearbyStatusTitle)
                    .font(.body.weight(.medium))
                Text(nearbyStatusSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isLoadingSession {
                ProgressView().controlSize(.small)
            } else {
                Button("重試") {
                    restartNearby()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private var nearbyStatusTitle: String {
        if isLoadingSession { return "正在載入帳號資料" }
        if session == nil { return "無法啟動附近加好友" }
        return nearbyService.isActive ? "正在搜尋附近的朋友" : "尚未啟動"
    }

    private var nearbyStatusSubtitle: String {
        if let sessionError { return sessionError }
        if session == nil { return "請確認已登入後再試一次。" }
        return "把手機靠近對方，保持此頁開啟。"
    }

    private func startNearby() {
        guard let session else { return }
        let payload = ProfileQRService.makeMutualPayload(
            userId: session.userId,
            empNo: session.empNo,
            displayName: session.userName
        )
        nearbyService.start(profile: payload)
    }

    private func restartNearby() {
        if session == nil {
            onRetrySession()
        }
        nearbyStartNonce = UUID()
        startNearby()
    }

    private func makeQRImage(session: SISSession) -> UIImage? {
        if sharesCredentials {
            guard let credentials = try? CredentialStore.shared.retrieveLDAPCredentials() else { return nil }
            return ProfileQRService.generateQRImage(
                for: ProfileQRService.makeCombinedPayload(
                    userId: session.userId,
                    empNo: session.empNo,
                    displayName: session.userName,
                    username: credentials.username,
                    password: credentials.password
                ),
                size: 600
            )
        }

        return ProfileQRService.generateQRImage(
            for: ProfileQRService.makeMutualPayload(
                userId: session.userId,
                empNo: session.empNo,
                displayName: session.userName
            ),
            size: 600
        )
    }

    private var qrUnavailableMessage: String {
        if let sessionError { return sessionError }
        if sharesCredentials && !CredentialStore.shared.hasLDAPCredentials() {
            return "尚未儲存 LDAP 帳號密碼，無法產生點名授權 QR Code。"
        }
        return "缺少學校帳號資料。"
    }

    private func peerRow(_ peer: NearbyPeerProfile, isAdded: Bool) -> some View {
        HStack(spacing: 12) {
            ProfileInitialCircle(name: peer.displayName, tint: AppTheme.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(peer.displayName).font(.body)
                Text(peer.empNo).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            if isAdded {
                Label("已新增", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
            } else {
                Button("加好友") {
                    guard !friendStore.isFriend(recordName: peer.id) else {
                        addedIds.insert(peer.id)
                        return
                    }
                    addedIds.insert(peer.id)
                    onRequestAddPeer(peer)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }

    private func incomingRequestRow(_ peer: NearbyPeerProfile) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "person.badge.plus")
                    .foregroundStyle(.green)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("\(peer.displayName) 已加你為好友")
                    .font(.body)
                Text("要加回對方嗎？")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("加好友") {
                guard !friendStore.isFriend(recordName: peer.id) else {
                    nearbyService.dismissIncomingRequest(id: peer.id)
                    addedIds.insert(peer.id)
                    return
                }
                addedIds.insert(peer.id)
                onAcceptIncomingPeer(peer)
                nearbyService.dismissIncomingRequest(id: peer.id)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.vertical, 2)
    }
}

private struct FriendQRScannerSheet: View {
    let onScanned: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                QRScannerView { qrString in
                    onScanned(qrString)
                }
                .ignoresSafeArea()

                VStack {
                    Spacer()
                    Text("掃描朋友的個人 QR Code")
                        .font(.subheadline).foregroundStyle(.white)
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

private struct AddFriendActionRow: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(tint.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct ProfileInitialCircle: View {
    let name: String
    let tint: Color

    var body: some View {
        Circle()
            .fill(tint.opacity(0.15))
            .frame(width: 44, height: 44)
            .overlay {
                Text(String(name.prefix(1)))
                    .font(.headline)
                    .foregroundStyle(tint)
            }
    }
}

// MARK: - Shared FriendRow (used here and in FriendDetailView)

struct FriendRow: View {
    let friend: FriendRecord

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(AppTheme.accent.opacity(0.15))
                .frame(width: 44, height: 44)
                .overlay {
                    Text(String(friend.displayName.prefix(1)))
                        .font(.headline)
                        .foregroundStyle(AppTheme.accent)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.displayName).font(.body)
                Text(friend.empNo).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    NavigationStack {
        FriendListView()
            .environment(AuthenticationManager())
    }
}
