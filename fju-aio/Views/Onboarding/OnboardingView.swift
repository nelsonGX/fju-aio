import SwiftUI
import AVFoundation

// MARK: - Onboarding View

struct OnboardingView: View {
    private let onComplete: () -> Void

    init(onComplete: @escaping () -> Void = {}) {
        self.onComplete = onComplete
    }

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("preferredMapsApp") private var preferredMapsApp = "apple"
    @State private var pageIndex: Int = 0
    /// Toggled true when Continue is pressed on the profile page, triggering a save in OnboardingProfilePage.
    @State private var profileSaveRequested = false
    @State private var isProfileSaving = false

    private let notificationManager = CourseNotificationManager.shared

    private let totalPages = 5
    private var isLastPage: Bool { pageIndex == totalPages - 1 }
    private var isProfilePage: Bool { pageIndex == 3 }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $pageIndex) {
                welcomePage.tag(0)
                scheduleAndLivePage.tag(1)
                mapPage.tag(2)
                profileSetupPage.tag(3)
                privacyPage.tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: pageIndex)

            bottomBar
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    // MARK: - Page 1: Welcome

    private var welcomePage: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(AppTheme.accent.opacity(0.12))
                        .frame(width: 120, height: 120)
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(AppTheme.accent)
                }
                VStack(spacing: 10) {
                    Text("歡迎使用")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("輔大 All In One")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("一個 App，整合所有輔大校務服務")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Page 2: Course Schedule + Live Activity

    private var scheduleAndLivePage: some View {
        VStack(spacing: 0) {
            OnboardingPreviewVideo(
                resourceName: "onboarding_step_1_preview",
                icon: "calendar",
                color: .blue,
                isActive: pageIndex == 1
            )
                .padding(.horizontal, 20)
                .padding(.top, 40)

            Spacer()

            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text("課表查詢")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("一眼掌握本週課程安排，上課前動態島即時提醒，再也不怕遲到。")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Toggle(isOn: Binding(
                    get: { notificationManager.isEnabled },
                    set: { notificationManager.isEnabled = $0 }
                )) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("開啟課程提醒通知")
                                .font(.body.weight(.medium))
                            Text("可在「設定」頁面隨時更改")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "bell.badge.fill")
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    // MARK: - Page 3: Campus Map

    private var mapPage: some View {
        VStack(spacing: 0) {
            OnboardingPreviewVideo(
                resourceName: "onboarding_step_2_preview",
                icon: "map.fill",
                color: .green,
                isActive: pageIndex == 2
            )
                .padding(.horizontal, 20)
                .padding(.top, 40)

            Spacer()

            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text("校園地圖")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("快速找到校內各建築位置，輕鬆導航前往。")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("預設導航應用程式")
                                .font(.body.weight(.medium))
                            Text("可在「設定」頁面隨時更改")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "location.fill")
                            .foregroundStyle(.green)
                    }

                    Picker("", selection: $preferredMapsApp) {
                        Text("Apple 地圖").tag("apple")
                        Text("Google 地圖").tag("google")
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    // MARK: - Page 4: Profile Setup

    private var profileSetupPage: some View {
        OnboardingProfilePage(
            onContinueTapped: $profileSaveRequested,
            isSaving: $isProfileSaving,
            onSaved: {
                withAnimation { pageIndex += 1 }
            }
        )
    }

    // MARK: - Page 5: Privacy

    private var privacyPage: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 28) {
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.12))
                            .frame(width: 90, height: 90)
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 42))
                            .foregroundStyle(.green)
                    }
                    Text("以防有人在意...")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                    Text("首先這不是輔大官方寫的，我們也沒有拿到錢(QQ)。再來這個 App 只是做興趣的，我們不會蒐集您的任何資料。")
                        .font(.caption)
                        .padding(16)
                }

                VStack(spacing: 12) {
                    PrivacyRow(
                        icon: "iphone",
                        color: .blue,
                        title: "帳號密碼僅存於裝置",
                        description: "學校帳號與密碼以 iOS Keychain 加密，僅存於本機裝置，不會上傳至任何伺服器。"
                    )
                    PrivacyRow(
                        icon: "icloud.fill",
                        color: .white,
                        title: "公開個人檔案由您決定",
                        description: "只有您主動填寫並儲存的內容，才會透過 iCloud 對外可見。隨時可在設定頁面關閉。"
                    )
                }
                .padding(.horizontal, 24)
            }
            Spacer()
        }
    }

    // MARK: - Shared Media Placeholder

    private func mediaPlaceholder(icon: String, color: Color, assetName: String) -> some View {
        Group {
            if let uiImage = UIImage(named: assetName) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                        .fill(color.opacity(0.08))
                    VStack(spacing: 10) {
                        Image(systemName: icon)
                            .font(.system(size: 52))
                            .foregroundStyle(color.opacity(0.4))
                        Text("預覽影片")
                            .font(.caption)
                            .foregroundStyle(Color.secondary.opacity(0.4))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 260)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 16) {
            HStack(spacing: 6) {
                ForEach(0..<totalPages, id: \.self) { i in
                    Capsule()
                        .fill(pageIndex == i ? AppTheme.accent : Color.secondary.opacity(0.25))
                        .frame(width: pageIndex == i ? 18 : 6, height: 6)
                        .animation(.spring(response: 0.3), value: pageIndex)
                }
            }

            Button {
                if isLastPage {
                    completeOnboarding()
                } else if isProfilePage {
                    // Signal OnboardingProfilePage to save, then advance when done
                    profileSaveRequested = true
                } else {
                    withAnimation {
                        pageIndex += 1
                    }
                }
            } label: {
                Group {
                    if isProfileSaving {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    } else {
                        Text(isLastPage ? "開始使用" : "繼續")
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(AppTheme.accent)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            }
            .buttonStyle(.plain)
            .disabled(isProfileSaving)
            .padding(.horizontal, 24)

            if !isLastPage {
                Button("跳過") {
                    completeOnboarding()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            } else {
                Color.clear.frame(height: 20)
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 32)
        .background(Color(.systemGroupedBackground))
    }

    private func completeOnboarding() {
        onComplete()
        hasCompletedOnboarding = true
    }
}

// MARK: - Onboarding Preview Video

private struct OnboardingPreviewVideo: View {
    let resourceName: String
    let icon: String
    let color: Color
    let isActive: Bool

    @State private var player = AVQueuePlayer()
    @State private var looper: AVPlayerLooper?
    @State private var didConfigurePlayer = false

    var body: some View {
        Group {
            if let url = Bundle.main.onboardingVideoURL(named: resourceName) {
                PlayerLayerView(player: player)
                    .onAppear {
                        configurePlayerIfNeeded(url: url)
                        updatePlayback()
                    }
                    .onDisappear {
                        player.pause()
                    }
                    .onChange(of: isActive) { _, _ in
                        updatePlayback()
                    }
            } else {
                mediaFallback
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
    }

    private var mediaFallback: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .fill(color.opacity(0.08))
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 52))
                    .foregroundStyle(color.opacity(0.4))
                Text("預覽影片")
                    .font(.caption)
                    .foregroundStyle(Color.secondary.opacity(0.4))
            }
        }
    }

    private func configurePlayerIfNeeded(url: URL) {
        guard !didConfigurePlayer else { return }

        let item = AVPlayerItem(url: url)
        looper = AVPlayerLooper(player: player, templateItem: item)
        player.isMuted = true
        player.actionAtItemEnd = .none
        didConfigurePlayer = true
    }

    private func updatePlayback() {
        if isActive {
            player.seek(to: .zero)
            player.play()
        } else {
            player.pause()
            player.seek(to: .zero)
        }
    }
}

private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerContainerView {
        let view = PlayerLayerContainerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PlayerLayerContainerView, context: Context) {
        uiView.playerLayer.player = player
    }
}

private final class PlayerLayerContainerView: UIView {
    override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}

private extension Bundle {
    func onboardingVideoURL(named name: String) -> URL? {
        url(forResource: name, withExtension: "mp4")
            ?? url(forResource: name, withExtension: "mp4", subdirectory: "Resources")
    }
}

// MARK: - Onboarding Profile Page

/// A full-featured profile setup page adapted for onboarding.
/// All fields mirror MyProfileView exactly, but saving only happens
/// when the parent signals via `onContinueTapped`, and on completion
/// it advances the page by resetting the binding and calling `onSaved`.
private struct OnboardingProfilePage: View {
    @Environment(AuthenticationManager.self) private var authManager
    @Environment(\.fjuService) private var service

    /// Parent sets this to true → we save → then call onSaved
    @Binding var onContinueTapped: Bool
    /// Parent binds this to show a spinner in the Continue button
    @Binding var isSaving: Bool
    /// Called after save completes (success or skip) so parent can advance
    let onSaved: () -> Void

    @AppStorage("myProfile.displayName") private var displayName = ""
    @AppStorage("myProfile.bio") private var bio = ""
    @AppStorage("myProfile.isPublished") private var isPublished = false
    @AppStorage("myProfile.shareSchedule") private var shareSchedule = false
    @AppStorage("myProfile.scheduleVisibility") private var scheduleVisibilityRaw = ScheduleVisibility.friendsOnly.rawValue

    @State private var socialLinks: [SocialLink] = []
    @State private var sisSession: SISSession?
    @State private var profileAvatarURL: URL?
    @State private var isLoading = false
    @State private var publishError: String?
    @State private var showAddLink = false
    @State private var showDisableConfirm = false
    @State private var showAvatarMessage = false
    @FocusState private var focusedField: ProfileField?

    private enum ProfileField: Hashable {
        case bio
        case socialLink(String)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Page header
                VStack(spacing: 8) {
                    Text("建立個人檔案")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("讓其他人可以在課表中找到你、查看你的連結；讓你可以跟同學加好友，互相分享課表（可略過）")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 32)
                .padding(.bottom, 20)
                .padding(.horizontal, 24)

                VStack(spacing: 0) {
                    // MARK: Identity row
                    HStack(spacing: 16) {
                        ProfileAvatarView(
                            name: sisSession?.userName ?? (displayName.isEmpty ? "學生姓名" : displayName),
                            avatarURL: profileAvatarURL,
                            size: 52
                        )
                        .onTapGesture { showAvatarMessage = true }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(sisSession?.userName ?? (displayName.isEmpty ? "學生姓名" : displayName))
                                .font(.title3.weight(.semibold))
                            Text(sisSession?.empNo ?? "410XXXXXX")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if isLoading {
                            ProgressView().scaleEffect(0.8)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                    Divider().padding(.leading, 16)

                    // MARK: Public profile toggle
                    Toggle(isOn: Binding(
                        get: { isPublished },
                        set: { newValue in
                            if newValue {
                                isPublished = true
                            } else {
                                showDisableConfirm = true
                            }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("啟用公開資料")
                                .font(.body)
                            isPublished ? nil :
                            Text("開啟後，你可以加入個人社群連結、分享課表給朋友。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(sisSession == nil)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                }
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                .padding(.horizontal, 20)

                if isPublished {
                    VStack(spacing: 0) {
                        HStack {
                            Text("課表分享")
                            Spacer()
                            Picker("課表分享", selection: scheduleVisibilityBinding) {
                                ForEach(ScheduleVisibility.allCases, id: \.rawValue) { visibility in
                                    Text(visibility.label).tag(visibility.rawValue)
                                }
                            }
                            .labelsHidden()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        Divider().padding(.leading, 16)

                        Text(scheduleVisibility.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    }
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                    // MARK: Bio
                    VStack(alignment: .leading, spacing: 0) {
                        Text("自我介紹")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                            .padding(.bottom, 6)

                        VStack(spacing: 0) {
                            TextField("讓朋友認識你（選填）", text: $bio, axis: .vertical)
                                .lineLimit(3, reservesSpace: true)
                                .focused($focusedField, equals: .bio)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                        }
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                        .padding(.horizontal, 20)
                    }

                    // MARK: Social links
                    VStack(alignment: .leading, spacing: 0) {
                        Text("社群連結")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                            .padding(.bottom, 6)

                        VStack(spacing: 0) {
                            ForEach(socialLinks.indices, id: \.self) { i in
                                HStack(spacing: 12) {
                                    SocialBrandIcon(platform: socialLinks[i].platform)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(socialLinks[i].platform.label)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        TextField(socialLinks[i].platform.placeholder,
                                                  text: Binding(
                                                    get: { socialLinks[i].handle },
                                                    set: { socialLinks[i].handle = $0 }
                                                  ))
                                        .font(.body)
                                        .autocorrectionDisabled()
                                        .textInputAutocapitalization(.never)
                                        .focused($focusedField, equals: .socialLink(socialLinks[i].id))
                                    }
                                    Spacer()
                                    Button {
                                        if focusedField == .socialLink(socialLinks[i].id) {
                                            focusedField = nil
                                        }
                                        socialLinks.remove(at: i)
                                        saveSocialLinks()
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(.red)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 11)

                                if i < socialLinks.count - 1 {
                                    Divider().padding(.leading, 60)
                                }
                            }

                            if !socialLinks.isEmpty {
                                Divider().padding(.leading, 16)
                            }

                            Button {
                                showAddLink = true
                            } label: {
                                Label("新增社群連結", systemImage: "plus.circle")
                                    .font(.body)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                        .padding(.horizontal, 20)
                    }
                }

                if let error = publishError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                }

                Spacer().frame(height: 24)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") {
                    focusedField = nil
                }
            }
        }
        .task {
            await loadSession()
            loadSocialLinks()
            await importRemoteProfileIfNeeded()
            await loadAvatar()
        }
        .onChange(of: onContinueTapped) { _, triggered in
            guard triggered else { return }
            focusedField = nil
            Task {
                await saveAndAdvance()
            }
        }
        .sheet(isPresented: $showAddLink) {
            AddSocialLinkSheet { newLink in
                socialLinks.append(newLink)
                saveSocialLinks()
            }
        }
        .confirmationDialog(
            "確認關閉公開資料",
            isPresented: $showDisableConfirm,
            titleVisibility: .visible
        ) {
            Button("關閉", role: .destructive) { isPublished = false }
            Button("取消", role: .cancel) {}
        } message: {
            Text("關閉後按「繼續」不會上傳任何資料。")
        }
        .alert("頭貼", isPresented: $showAvatarMessage) {
            Button("確定", role: .cancel) {}
        } message: {
            Text("請前往 TronClass 更改這個頭貼")
        }
    }

    // MARK: - Save local choices & advance

    @MainActor
    private func saveAndAdvance() async {
        onContinueTapped = false
        publishError = nil
        saveSocialLinks()

        guard isPublished, let session = sisSession else {
            onSaved()
            return
        }

        isSaving = true
        defer { isSaving = false }
        if displayName.isEmpty {
            displayName = session.userName
        }
        onSaved()
    }

    // MARK: - Helpers

    private func loadSession() async {
        isLoading = true
        defer { isLoading = false }
        if let session = try? await authManager.getValidSISSession() {
            sisSession = session
        }
    }

    @MainActor
    private func importRemoteProfileIfNeeded() async {
        guard let session = sisSession else { return }
        let recordName = ProfileIdentity.publicRecordName(for: session)
        guard let remote = try? await CloudKitProfileService.shared.fetchProfile(recordName: recordName) else { return }

        isPublished = true
        if UserDefaults.standard.object(forKey: "myProfile.displayName") == nil || displayName.isEmpty {
            displayName = remote.displayName
        }
        if UserDefaults.standard.object(forKey: "myProfile.bio") == nil {
            bio = remote.bio ?? ""
        }
        if UserDefaults.standard.object(forKey: socialLinksKey) == nil {
            socialLinks = remote.socialLinks
            saveSocialLinks()
        }
        if profileAvatarURL == nil, let remoteAvatarURL = remote.avatarURL {
            profileAvatarURL = remoteAvatarURL
        }
    }

    private func loadAvatar() async {
        if let urlString = try? await TronClassAPIService.shared.getCurrentUserAvatarURL(),
           let url = URL(string: urlString) {
            profileAvatarURL = url
        }
    }

    private let socialLinksKey = "myProfile.socialLinks"

    private func loadSocialLinks() {
        guard let data = UserDefaults.standard.data(forKey: socialLinksKey),
              let decoded = try? JSONDecoder().decode([SocialLink].self, from: data) else { return }
        socialLinks = decoded
    }

    private func saveSocialLinks() {
        if let data = try? JSONEncoder().encode(socialLinks) {
            UserDefaults.standard.set(data, forKey: socialLinksKey)
        }
    }

    private var scheduleVisibility: ScheduleVisibility {
        if let visibility = ScheduleVisibility(rawValue: scheduleVisibilityRaw) {
            return visibility
        }
        return shareSchedule ? .public : .friendsOnly
    }

    private var scheduleVisibilityBinding: Binding<String> {
        Binding(
            get: { scheduleVisibility.rawValue },
            set: { newValue in
                scheduleVisibilityRaw = newValue
                shareSchedule = newValue == ScheduleVisibility.public.rawValue
            }
        )
    }

    private func buildSnapshot(session: SISSession) async -> FriendScheduleSnapshot? {
        let cache = AppCache.shared

        let semesters: [String]
        if let cached = cache.getSemesters(), !cached.isEmpty {
            semesters = cached
        } else if let fetched = try? await service.fetchAvailableSemesters(), !fetched.isEmpty {
            semesters = fetched
            cache.setSemesters(fetched)
        } else {
            return nil
        }

        let semester = semesters[0]
        let courses: [Course]
        if let cached = cache.getCourses(semester: semester), !cached.isEmpty {
            courses = cached
        } else if let fetched = try? await service.fetchCourses(semester: semester), !fetched.isEmpty {
            courses = fetched
            cache.setCourses(fetched, semester: semester)
        } else {
            return nil
        }

        return FriendScheduleSnapshot(
            ownerUserId: session.userId,
            ownerDisplayName: session.userName,
            semester: semester,
            courses: courses.map { PublicCourseInfo(from: $0) },
            updatedAt: Date()
        )
    }
}

// MARK: - Add Social Link Sheet (shared helper used from onboarding profile page)

private struct AddSocialLinkSheet: View {
    let onAdd: (SocialLink) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPlatform: SocialPlatform = .instagram
    @State private var handle = ""
    @FocusState private var isHandleFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                Section("平台") {
                    Picker("選擇平台", selection: $selectedPlatform) {
                        ForEach(SocialPlatform.allCases, id: \.self) { platform in
                            HStack {
                                SocialBrandIcon(platform: platform, size: 24)
                                Text(platform.label)
                            }
                            .tag(platform)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .onChange(of: selectedPlatform) { _, _ in handle = "" }
                }
                Section("帳號 / 連結") {
                    HStack {
                        SocialBrandIcon(platform: selectedPlatform)
                        TextField(selectedPlatform.placeholder, text: $handle)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .focused($isHandleFocused)
                    }
                }
                if !handle.trimmingCharacters(in: .whitespaces).isEmpty,
                   let url = selectedPlatform.url(for: handle) {
                    Section("預覽連結") {
                        Text(url.absoluteString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("新增社群連結")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("新增") {
                        let link = SocialLink(platform: selectedPlatform,
                                             handle: handle.trimmingCharacters(in: .whitespaces))
                        onAdd(link)
                        dismiss()
                    }
                    .disabled(handle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") {
                        isHandleFocused = false
                    }
                }
            }
        }
    }
}

// MARK: - Privacy Row

private struct PrivacyRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(color)
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.smallCornerRadius))
    }
}

#Preview {
    OnboardingView()
        .environment(AuthenticationManager())
}
