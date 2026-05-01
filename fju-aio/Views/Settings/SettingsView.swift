import SwiftUI

struct SettingsView: View {
    @Environment(AuthenticationManager.self) private var authManager
    @State private var versionTapCount = 0
    @State private var showDebugScreen = false
    @State private var showLogoutAlert = false
    @State private var sisSession: SISSession?
    @State private var isLoadingSession = false
    @State private var friendStore = FriendStore.shared
    @State private var profileAvatarURL: URL?
    @State private var showAvatarMessage = false
    private let notificationManager = CourseNotificationManager.shared
    private let syncStatus = SyncStatusManager.shared
    @AppStorage("preferredMapsApp") private var preferredMapsApp = "apple"
    @AppStorage("openLinksInApp") private var openLinksInApp = true
    
    var body: some View {
        List {
            Section("帳號") {
                NavigationLink(destination: MyProfileView()) {
                    HStack {
                        ProfileAvatarView(
                            name: sisSession?.userName ?? "學生姓名",
                            avatarURL: profileAvatarURL,
                            size: 52
                        )
                        .onTapGesture { showAvatarMessage = true }

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
                }
            }

            // MARK: 好友（standalone, no title）
            Section {
                NavigationLink(destination: FriendListView()) {
                    SettingsFriendRow(friendCount: friendStore.friends.count)
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

                Picker("開啟連結方式", selection: $openLinksInApp) {
                    Text("App 內瀏覽器").tag(true)
                    Text("外部瀏覽器").tag(false)
                }
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
                    Text(versionString)
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

                Link(destination: URL(string: "https://github.com/FJU-Devs/fju-aio")!) {
                    HStack {
                        Text("在 GitHub 上查看")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    showLogoutAlert = true
                } label: {
                    HStack {
                        Spacer()
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("登出")
                        Spacer()
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
            await loadProfileAvatar()
        }
        .refreshable {
            await loadSISSession()
            await loadProfileAvatar()
        }
        .alert("頭貼", isPresented: $showAvatarMessage) {
            Button("確定", role: .cancel) {}
        } message: {
            Text("請前往 TronClass 更改這個頭貼")
        }
    }
    
    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let hash = Bundle.main.infoDictionary?["GitCommitHash"] as? String ?? ""
        return hash.isEmpty ? version : "\(version) (\(hash))"
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

    private func loadProfileAvatar() async {
        if let avatar = try? await TronClassAPIService.shared.getCurrentUserAvatarURL(),
           let url = URL(string: avatar) {
            profileAvatarURL = url
        }
    }
    
    private func performLogout() async {
        do {
            try await authManager.logout()
        } catch {
            print("登出失敗: \(error)")
        }
    }
}

private struct SettingsFriendRow: View {
    let friendCount: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.2.fill")
                .font(.title3)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 36, height: 36)
                .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text("好友")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text(friendCount == 0 ? "查看與分享個人 QR Code" : "\(friendCount) 位朋友")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environment(\.fjuService, FJUService.shared)
            .environment(AuthenticationManager())
    }
}
