import SwiftUI

// MARK: - FriendDetailView

struct FriendDetailView: View {
    let friend: FriendRecord

    @State private var profile: PublicProfile?
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var friendStore = FriendStore.shared

    // live credential status from store
    private var currentFriend: FriendRecord {
        friendStore.friends.first { $0.id == friend.id } ?? friend
    }

    @State private var showCredentialScanner = false
    @State private var credentialScanError: String?
    @State private var showDeleteCredConfirm = false

    var body: some View {
        List {
            // MARK: Identity
            Section {
                HStack(spacing: 16) {
                    Circle()
                        .fill(AppTheme.accent.opacity(0.15))
                        .frame(width: 56, height: 56)
                        .overlay {
                            Text(String(friend.displayName.prefix(1)))
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(AppTheme.accent)
                        }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile?.displayName ?? friend.displayName)
                            .font(.title3.weight(.semibold))
                        Text(friend.empNo)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            // MARK: Bio (standalone section)
            if let bio = profile?.bio, !bio.isEmpty {
                Section("自我介紹") {
                    Text(bio)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
            }

            // MARK: Social Links (dynamic)
            let links = profile?.socialLinks.filter { !$0.handle.trimmingCharacters(in: .whitespaces).isEmpty } ?? []
            if !links.isEmpty {
                Section("聯絡方式") {
                    ForEach(links) { link in
                        SocialLinkRow(link: link)
                    }
                }
            }

            // MARK: Rollcall Authorisation
            Section {
                if currentFriend.hasStoredCredentials {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundStyle(.green)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("已儲存點名授權")
                                .font(.body)
                            Text("你可以在簽到頁面替此朋友點名")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button(role: .destructive) {
                        showDeleteCredConfirm = true
                    } label: {
                        Label("撤銷授權（刪除帳密）", systemImage: "trash")
                    }
                } else {
                    HStack(spacing: 12) {
                        Image(systemName: "shield.slash")
                            .foregroundStyle(.secondary)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("尚未授權點名")
                                .font(.body)
                            Text("請對方在「我的資料」顯示點名 QR Code，再點下方按鈕掃描")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button {
                        showCredentialScanner = true
                    } label: {
                        Label("掃描對方的點名 QR Code", systemImage: "qrcode.viewfinder")
                    }
                    .foregroundStyle(AppTheme.accent)
                }

                if let err = credentialScanError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("點名授權")
            } footer: {
                if !currentFriend.hasStoredCredentials {
                    Text("對方的帳號密碼僅儲存於你的裝置 Keychain，不會上傳至任何伺服器。")
                }
            }

            // MARK: Schedule Snapshot
            Section("課表") {
                if isLoading && profile == nil {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("載入中...").foregroundStyle(.secondary)
                    }
                } else if let snapshot = profile?.scheduleSnapshot {
                    Text("學期：\(snapshot.semester) · 更新：\(snapshot.updatedAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(sortedCourses(snapshot.courses)) { course in
                        FriendCourseRow(course: course)
                    }
                } else {
                    Text("此朋友尚未發布課表，或課表尚未更新。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = loadError {
                Section {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(profile?.displayName ?? friend.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadProfile() }
        .refreshable { await loadProfile() }
        .sheet(isPresented: $showCredentialScanner) {
            CredentialScannerSheet(friend: currentFriend) { userId, displayName, username, password in
                showCredentialScanner = false
                if userId == (currentFriend.cachedProfile?.userId ?? -1) ||
                   username == currentFriend.empNo ||
                   displayName == currentFriend.displayName {
                    friendStore.saveCredentials(
                        for: currentFriend.id,
                        username: username,
                        password: password
                    )
                } else {
                    credentialScanError = "此 QR Code 不屬於 \(currentFriend.displayName)，請讓對方重新顯示。"
                }
            }
        }
        .confirmationDialog("撤銷點名授權", isPresented: $showDeleteCredConfirm, titleVisibility: .visible) {
            Button("刪除帳號密碼", role: .destructive) {
                friendStore.deleteCredentials(for: currentFriend.id)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("刪除後將無法在簽到時替 \(currentFriend.displayName) 代為點名，需要重新掃描授權。")
        }
    }

    private func loadProfile() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        if let cached = friend.cachedProfile { profile = cached }

        do {
            if let fresh = try await CloudKitProfileService.shared.fetchProfile(recordName: friend.id) {
                profile = fresh
                FriendStore.shared.updateCachedProfile(fresh, for: friend.id)
            }
        } catch {
            if profile == nil {
                loadError = "無法載入資料：\(error.localizedDescription)"
            }
        }
    }

    private func sortedCourses(_ courses: [PublicCourseInfo]) -> [PublicCourseInfo] {
        courses.sorted {
            let dayA = dayOrder($0.dayOfWeek), dayB = dayOrder($1.dayOfWeek)
            return dayA != dayB ? dayA < dayB : $0.startPeriod < $1.startPeriod
        }
    }

    private func dayOrder(_ day: String) -> Int {
        ["一", "二", "三", "四", "五", "六", "日"].firstIndex(of: day) ?? 99
    }
}

// MARK: - Social Link Row (renders a SocialLink from the dynamic array)

private struct SocialLinkRow: View {
    let link: SocialLink
    @Environment(\.openURL) private var openURL

    var body: some View {
        let content = HStack(spacing: 12) {
            SocialBrandIcon(platform: link.platform)

            VStack(alignment: .leading, spacing: 1) {
                Text(link.platform.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(link.displayHandle)
                    .font(.body)
            }

            Spacer()

            if link.resolvedURL != nil {
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }

        if let url = link.resolvedURL {
            Link(destination: url) { content }
        } else {
            content
        }
    }
}

// MARK: - Friend Course Row

private struct FriendCourseRow: View {
    let course: PublicCourseInfo

    private var periodLabel: String {
        let s = FJUPeriod.periodLabel(for: course.startPeriod)
        let e = FJUPeriod.periodLabel(for: course.endPeriod)
        return s == e ? "第\(s)節" : "第\(s)-\(e)節"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(course.name).font(.body)
            HStack(spacing: 12) {
                Label("星期\(course.dayOfWeek) \(periodLabel)", systemImage: "clock")
                Label(course.location, systemImage: "mappin")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}


// MARK: - Credential Scanner Sheet
// Accepts both group_rollcall and combined QR codes

private struct CredentialScannerSheet: View {
    let friend: FriendRecord
    /// Callback: (sharerUserId, sharerDisplayName, username, password)
    let onScanned: (Int, String, String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var scanError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                QRScannerView { qrString in
                    switch ProfileQRService.parse(qrString: qrString) {
                    case .groupRollcall(let payload):
                        onScanned(payload.sharerUserId, payload.sharerDisplayName, payload.username, payload.password)
                    case .combined(let payload):
                        onScanned(payload.userId, payload.displayName, payload.username, payload.password)
                    case .profile, .mutual:
                        scanError = "這是個人 QR Code，請讓對方開啟「包含點名授權」選項後再顯示 QR Code"
                    case .unknown:
                        scanError = "無法識別此 QR Code"
                    }
                }
                .ignoresSafeArea()

                VStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Text("掃描對方的點名 QR Code")
                            .font(.subheadline).foregroundStyle(.white)
                        if let err = scanError {
                            Text(err).font(.caption).foregroundStyle(.orange)
                        }
                    }
                    .padding()
                    .background(.black.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.bottom, 48)
                }
            }
            .navigationTitle("掃描點名授權")
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
    NavigationStack {
        FriendDetailView(friend: FriendRecord(
            id: "preview",
            empNo: "410123456",
            displayName: "王小明",
            cachedProfile: nil,
            addedAt: Date()
        ))
    }
}
