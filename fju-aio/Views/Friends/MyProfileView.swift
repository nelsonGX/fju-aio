import SwiftUI

// MARK: - MyProfileView

struct MyProfileView: View {
    @Environment(AuthenticationManager.self) private var authManager

    @AppStorage("myProfile.displayName") private var displayName = ""
    @AppStorage("myProfile.bio") private var bio = ""
    @AppStorage("myProfile.isPublished") private var isPublished = false
    @AppStorage("myProfile.shareSchedule") private var shareSchedule = false

    // Social links are stored as JSON in UserDefaults (AppStorage can't hold [SocialLink])
    @State private var socialLinks: [SocialLink] = []

    @State private var sisSession: SISSession?
    @State private var isLoading = false
    @State private var showAddLink = false
    @State private var showDisableConfirm = false
    @State private var profileAvatarURL: URL?
    @State private var showAvatarMessage = false

    // Auto-save state
    @State private var saveTask: Task<Void, Never>?
    @State private var publishError: String?

    private let syncStatus = SyncStatusManager.shared

    var body: some View {
        List {
            // MARK: Identity + Preview (top)
            Section {
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
                }
                .padding(.vertical, 4)

                if isPublished, let previewProfile {
                    NavigationLink {
                        PublicProfilePreviewView(profile: previewProfile, avatarURL: profileAvatarURL)
                    } label: {
                        Label("預覽公開資料", systemImage: "eye.fill")
                    }
                }
            } header: {
                Text("身份")
            } footer: {
                Text("姓名與學號來自學校帳號，無法在此修改。")
            }

            // MARK: Public Profile Toggle
            Section {
                Toggle("啟用公開資料", isOn: Binding(
                    get: { isPublished },
                    set: { newValue in
                        if newValue {
                            isPublished = true
                            scheduleSave()
                        } else {
                            showDisableConfirm = true
                        }
                    }
                ))
                .disabled(sisSession == nil)

                if isPublished {
                    Text("你的資料已公開，朋友可透過 QR Code 找到你。關閉後將刪除雲端資料。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("開啟後，朋友可掃描你的個人 QR Code 加你為好友，並查看你的課表與聯絡方式。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("公開資料")
            }

            // MARK: Profile fields (only shown when enabled)
            if isPublished {
                Section {
                    Toggle("公開我的課表", isOn: $shareSchedule)
                } footer: {
                    Text("變更後將自動同步到雲端。")
                }

                // Bio
                Section("自我介紹") {
                    TextField("讓朋友認識你（選填）", text: $bio, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }

                // Social Links
                Section {
                    ForEach($socialLinks) { $link in
                        SocialLinkEditRow(link: $link)
                    }
                    .onDelete { offsets in
                        socialLinks.remove(atOffsets: offsets)
                        saveSocialLinks()
                        scheduleSave()
                    }

                    Button {
                        showAddLink = true
                    } label: {
                        Label("新增社群連結", systemImage: "plus.circle")
                    }
                } header: {
                    Text("社群連結")
                }

                if let error = publishError {
                    Section {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .navigationTitle("我的資料")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isLoading { ProgressView() }
        }
        .task {
            await loadSession()
            loadSocialLinks()
            await loadProfileAvatar()
        }
        .onDisappear {
            // Flush any pending debounced save immediately on navigate-away
            saveTask?.cancel()
            if isPublished, sisSession != nil {
                Task { await publishProfileNow() }
            }
        }
        .onChange(of: bio) { _, _ in scheduleSave() }
        .onChange(of: shareSchedule) { _, _ in scheduleSave() }
        .onChange(of: socialLinks) { _, _ in
            saveSocialLinks()
            scheduleSave()
        }
        .sheet(isPresented: $showAddLink) {
            AddSocialLinkSheet { newLink in
                socialLinks.append(newLink)
                saveSocialLinks()
                scheduleSave()
            }
        }
        .confirmationDialog(
            "確認關閉公開資料",
            isPresented: $showDisableConfirm,
            titleVisibility: .visible
        ) {
            Button("關閉並刪除雲端資料", role: .destructive) {
                Task { await disableProfile() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("關閉後，你的公開資料（包含課表與社群連結）將從雲端刪除，好友將無法再看到你的資料。")
        }
        .alert("頭貼", isPresented: $showAvatarMessage) {
            Button("確定", role: .cancel) {}
        } message: {
            Text("請前往 TronClass 更改這個頭貼")
        }
    }

    // MARK: - Session

    private func loadSession() async {
        isLoading = true
        defer { isLoading = false }
        do {
            sisSession = try await authManager.getValidSISSession()
            if displayName.isEmpty, let name = sisSession?.userName {
                displayName = name
            }
        } catch {
            sisSession = nil
        }
    }

    private func loadProfileAvatar() async {
        if let avatar = try? await TronClassAPIService.shared.getCurrentUserAvatarURL(),
           let url = URL(string: avatar) {
            profileAvatarURL = url
        }
    }

    // MARK: - Social Links Persistence (UserDefaults JSON)

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

    // MARK: - Auto-save (debounced)

    /// Schedule a debounced save 0.8 s after the last change.
    private func scheduleSave() {
        guard isPublished, sisSession != nil else { return }
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            await publishProfileNow()
        }
    }

    @MainActor
    private func publishProfileNow() async {
        guard let session = sisSession, isPublished else { return }
        publishError = nil

        await syncStatus.withSync("儲存中...") {
            let effectiveName = displayName.isEmpty ? session.userName : displayName
            let snapshot = shareSchedule ? buildSnapshot(session: session) : nil

            let profile = PublicProfile(
                cloudKitRecordName: ProfileQRService.stableDeviceToken(),
                userId: session.userId,
                empNo: session.empNo,
                displayName: effectiveName,
                bio: bio.isEmpty ? nil : bio,
                socialLinks: socialLinks,
                scheduleSnapshot: snapshot,
                lastUpdated: Date()
            )

            do {
                try await CloudKitProfileService.shared.publishProfile(profile)
                isPublished = true
            } catch {
                publishError = "儲存失敗：\(error.localizedDescription)"
            }
        }
    }

    // MARK: - Disable (delete from CloudKit)

    private func disableProfile() async {
        let token = ProfileQRService.stableDeviceToken()
        do {
            try await CloudKitProfileService.shared.deleteProfile(recordName: token)
        } catch {
            // Silently ignore delete errors (record may not exist)
        }
        isPublished = false
    }

    // MARK: - Schedule Snapshot

    private func buildSnapshot(session: SISSession) -> FriendScheduleSnapshot? {
        let cache = AppCache.shared
        guard let semesters = cache.getSemesters(), let semester = semesters.first,
              let courses = cache.getCourses(semester: semester), !courses.isEmpty else { return nil }
        return FriendScheduleSnapshot(
            ownerUserId: session.userId,
            ownerDisplayName: session.userName,
            semester: semester,
            courses: courses.map { PublicCourseInfo(from: $0) },
            updatedAt: Date()
        )
    }

    private var previewProfile: PublicProfile? {
        guard let session = sisSession else { return nil }
        return PublicProfile(
            cloudKitRecordName: ProfileQRService.stableDeviceToken(),
            userId: session.userId,
            empNo: session.empNo,
            displayName: displayName.isEmpty ? session.userName : displayName,
            bio: bio.isEmpty ? nil : bio,
            socialLinks: socialLinks,
            scheduleSnapshot: shareSchedule ? buildSnapshot(session: session) : nil,
            lastUpdated: Date()
        )
    }
}

// MARK: - Social Link Edit Row (inline editing within the list)

private struct SocialLinkEditRow: View {
    @Binding var link: SocialLink

    var body: some View {
        HStack(spacing: 12) {
            SocialBrandIcon(platform: link.platform)

            VStack(alignment: .leading, spacing: 2) {
                Text(link.platform.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(link.platform.placeholder, text: $link.handle)
                    .font(.body)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
        }
    }
}

// MARK: - Add Social Link Sheet

private struct AddSocialLinkSheet: View {
    let onAdd: (SocialLink) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPlatform: SocialPlatform = .instagram
    @State private var handle = ""

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
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("新增") {
                        let link = SocialLink(platform: selectedPlatform, handle: handle.trimmingCharacters(in: .whitespaces))
                        onAdd(link)
                        dismiss()
                    }
                    .disabled(handle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        MyProfileView()
            .environment(AuthenticationManager())
    }
}
