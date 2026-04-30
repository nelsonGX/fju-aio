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
    @State private var showScanner = false
    @State private var showMyQR = false
    @State private var scanError: String?
    @State private var lastScannedInfo: String?
    @State private var sisSession: SISSession?
    @State private var isLoadingSession = false
    @State private var isQRButtonLoading = false
    @State private var sessionError: String?
    @AppStorage("friendList.shareCredentialQRCode") private var shareCredentialQRCode = false

    var body: some View {
        List {
            // MARK: My QR Card
            Section {
                Button {
                    guard !isQRButtonLoading else { return }
                    Task { await openQRSheet() }
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(AppTheme.accent.opacity(0.12))
                                .frame(width: 44, height: 44)
                            if isQRButtonLoading {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(AppTheme.accent)
                            } else {
                                Image(systemName: "qrcode")
                                    .font(.title2)
                                    .foregroundStyle(AppTheme.accent)
                            }
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("顯示我的 QR Code")
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                            Text("讓朋友掃描來加你為好友")
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
                .buttonStyle(.plain)
            }

            // MARK: 你的朋友
            Section("你的朋友") {
                if friendStore.friends.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "person.2.slash")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text("點右上角掃描對方的個人 QR Code 來新增好友")
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
                        NavigationLink(value: friend) {
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
                    showScanner = true
                } label: {
                    Image(systemName: "qrcode.viewfinder")
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
        .sheet(isPresented: $showScanner) {
            AddFriendScannerSheet { qrString in
                showScanner = false
                handleScanned(qrString)
            }
        }
        .sheet(isPresented: $showMyQR) {
            MyProfileQRSheet(
                session: sisSession,
                sharesCredentials: $shareCredentialQRCode,
                isLoading: isLoadingSession,
                errorMessage: sessionError,
                onRetry: { Task { await loadSession(force: true) } }
            )
        }
        .task { await loadSession() }
        .refreshable { await refreshAll() }
    }

    @MainActor
    private func openQRSheet() async {
        isQRButtonLoading = true
        defer { isQRButtonLoading = false }
        // Fetch session if not already available
        if sisSession == nil {
            await loadSession(force: true)
        }
        showMyQR = true
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
            // Prevent adding yourself
            if payload.cloudKitRecordName == myToken {
                scanError = "這是你自己的 QR Code，無法加自己為好友。"
                return
            }
            friendStore.addFriend(from: payload)
            lastScannedInfo = "已新增好友：\(payload.displayName)（\(payload.empNo)）"
            Task {
                if let profile = try? await CloudKitProfileService.shared.fetchProfile(recordName: payload.cloudKitRecordName) {
                    await MainActor.run {
                        friendStore.updateCachedProfile(profile, for: payload.cloudKitRecordName)
                    }
                }
            }
        case .combined(let payload):
            // Prevent adding yourself
            if payload.cloudKitRecordName == myToken {
                scanError = "這是你自己的 QR Code，無法加自己為好友。"
                return
            }
            // Add as friend (using profile portion)
            let profilePayload = ProfileQRPayload(
                version: payload.version,
                type: "profile",
                cloudKitRecordName: payload.cloudKitRecordName,
                empNo: payload.empNo,
                displayName: payload.displayName,
                userId: payload.userId
            )
            friendStore.addFriend(from: profilePayload)
            // Also store rollcall credentials
            if let friendId = friendStore.friends.first(where: { $0.id == payload.cloudKitRecordName })?.id {
                friendStore.saveCredentials(for: friendId, username: payload.username, password: payload.password)
            }
            lastScannedInfo = "已新增好友：\(payload.displayName)（\(payload.empNo)）並儲存點名授權"
            Task {
                if let profile = try? await CloudKitProfileService.shared.fetchProfile(recordName: payload.cloudKitRecordName) {
                    await MainActor.run {
                        friendStore.updateCachedProfile(profile, for: payload.cloudKitRecordName)
                    }
                }
            }
        case .groupRollcall:
            scanError = "這是點名 QR Code，請在簽到頁面使用。"
        case .unknown:
            scanError = "無法識別此 QR Code。"
        }
    }
}

// MARK: - My Profile QR Sheet (inline, shown from friend list)

private struct MyProfileQRSheet: View {
    let session: SISSession?
    @Binding var sharesCredentials: Bool
    let isLoading: Bool
    let errorMessage: String?
    let onRetry: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text(sharesCredentials ? "讓朋友掃描來取得點名授權，同時可加你為好友" : "讓朋友掃描來加你為好友")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if let session,
                   let image = makeQRImage(session: session) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 260, height: 260)
                        .padding()
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(radius: 8)
                } else if isLoading {
                    ProgressView("載入中...")
                        .frame(width: 260, height: 260)
                } else {
                    ContentUnavailableView {
                        Label("無法顯示 QR Code", systemImage: "qrcode")
                    } description: {
                        Text(unavailableMessage)
                    } actions: {
                        Button("重試", action: onRetry)
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(minHeight: 260)
                }

                if let session {
                    VStack(spacing: 4) {
                        Text(session.userName).font(.headline)
                        Text(session.empNo).font(.subheadline).foregroundStyle(.secondary)
                    }
                }

                // Share credentials toggle
                Toggle(isOn: $sharesCredentials) {
                    Label("包含點名授權", systemImage: "person.badge.key.fill")
                }
                .foregroundStyle(sharesCredentials ? .orange : .primary)
                .padding(.horizontal)

                if sharesCredentials {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("這個 QR Code 含有帳號密碼。分享後對方可以替你點名，請勿任意外流。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    .padding(12)
                    .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)
                }
                Spacer()
            }
            .padding(.top, 32)
            .navigationTitle("個人 QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("關閉") { dismiss() } }
            }
        }
    }

    private func makeQRImage(session: SISSession) -> UIImage? {
        if sharesCredentials {
            guard let credentials = try? CredentialStore.shared.retrieveLDAPCredentials() else { return nil }
            // Combined QR: embed both profile info and credential info
            // We use the group_rollcall type which already carries displayName/userId,
            // and the scanner in FriendListView also accepts profile payloads.
            // Instead, we create a combined payload via groupRollcall (credential sharing takes priority).
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
            for: ProfileQRService.makeProfilePayload(
                userId: session.userId,
                empNo: session.empNo,
                displayName: session.userName
            ),
            size: 600
        )
    }

    private var unavailableMessage: String {
        if let errorMessage { return errorMessage }
        if sharesCredentials && !CredentialStore.shared.hasLDAPCredentials() {
            return "尚未儲存 LDAP 帳號密碼，無法產生點名授權 QR Code。"
        }
        return "缺少學校帳號資料。"
    }
}

// MARK: - Add Friend Scanner Sheet

private struct AddFriendScannerSheet: View {
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                QRScannerView(onScan: onScan).ignoresSafeArea()
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
