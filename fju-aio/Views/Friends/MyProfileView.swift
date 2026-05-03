import SwiftUI
import os.log

// MARK: - MyProfileView

struct MyProfileView: View {
    @Environment(AuthenticationManager.self) private var authManager
    @Environment(\.fjuService) private var service

    @AppStorage("myProfile.displayName") private var displayName = ""
    @AppStorage("myProfile.bio") private var bio = ""
    @AppStorage("myProfile.isPublished") private var isPublished = false
    @AppStorage("myProfile.shareSchedule") private var shareSchedule = false
    @AppStorage("myProfile.scheduleVisibility") private var scheduleVisibilityRaw = ScheduleVisibility.friendsOnly.rawValue

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
    @State private var hasPendingProfileSave = false
    @State private var isPublishingProfile = false
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
                    Text("你的資料已公開，其他人可以在課表中找到你、查看你的連結；你可以跟同學加好友，互相分享課表。關閉後將刪除雲端資料。")
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
                    Picker("課表分享", selection: scheduleVisibilityBinding) {
                        ForEach(ScheduleVisibility.allCases, id: \.rawValue) { visibility in
                            Text(visibility.label).tag(visibility.rawValue)
                        }
                    }
                    Text(scheduleVisibility.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        .adaptiveListContentMargins()
        .navigationTitle("我的資料")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isLoading { ProgressView() }
        }
        .task {
            await loadSession()
            loadSocialLinks()
            await importRemoteProfileIfNeeded()
            await loadProfileAvatar()
        }
        .onDisappear {
            // Flush only real pending edits. Preview navigation also triggers onDisappear.
            saveTask?.cancel()
            if hasPendingProfileSave, isPublished, sisSession != nil {
                Task { await publishProfileNow() }
            }
        }
        .onChange(of: bio) { _, _ in scheduleSave() }
        .onChange(of: scheduleVisibilityRaw) { _, _ in scheduleSave() }
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
        } catch {
            sisSession = nil
        }
    }

    @MainActor
    private func importRemoteProfileIfNeeded() async {
        guard let session = sisSession else { return }
        let recordName = ProfileIdentity.publicRecordName(for: session)
        guard let remote = try? await CloudKitProfileService.shared.fetchProfile(recordName: recordName) else { return }

        isPublished = true
        if !hasStoredProfileValue("myProfile.displayName") || displayName.isEmpty {
            displayName = remote.displayName
        }
        if !hasStoredProfileValue("myProfile.bio") {
            bio = remote.bio ?? ""
        }
        if !hasStoredProfileValue(socialLinksKey) {
            socialLinks = remote.socialLinks
            saveSocialLinks()
        }
        if profileAvatarURL == nil, let remoteAvatarURL = remote.avatarURL {
            profileAvatarURL = remoteAvatarURL
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
        hasPendingProfileSave = true
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
        guard hasPendingProfileSave || profileAvatarURL == nil else { return }
        guard !isPublishingProfile else { return }
        isPublishingProfile = true
        defer { isPublishingProfile = false }

        publishError = nil
        if profileAvatarURL == nil {
            await loadProfileAvatar()
        }

        let effectiveName = displayName.isEmpty ? session.userName : displayName
        let visibility = self.scheduleVisibility
        snapshotLogger.info("📤 publishProfileNow: scheduleVisibility=\(visibility.rawValue, privacy: .public), userId=\(session.userId, privacy: .private), empNo=\(session.empNo, privacy: .private)")

        let existingProfile = try? await CloudKitProfileService.shared.fetchProfile(
            recordName: ProfileIdentity.publicRecordName(userId: session.userId)
        )
        let bioToPublish = hasStoredProfileValue("myProfile.bio")
            ? (bio.isEmpty ? nil : bio)
            : existingProfile?.bio
        let socialLinksToPublish = hasStoredProfileValue(socialLinksKey)
            ? socialLinks
            : (existingProfile?.socialLinks ?? socialLinks)
        let displayNameToPublish = hasStoredProfileValue("myProfile.displayName") && !displayName.isEmpty
            ? displayName
            : (existingProfile?.displayName ?? effectiveName)
        let avatarURLStringToPublish = profileAvatarURL?.absoluteString ?? existingProfile?.avatarURLString

        let snapshot = visibility == .off ? nil : await buildSnapshot(session: session)
        let publicSnapshot = visibility == .public ? snapshot : nil
        let scheduleToken = ProfileQRService.scheduleShareToken()
        snapshotLogger.info("📦 publishProfileNow: snapshot is \(snapshot == nil ? "nil" : "present (\(snapshot!.courses.count) courses, semester \(snapshot!.semester))", privacy: .public)")

        let friendScheduleChanged = await hasFriendScheduleChanges(
            visibility: visibility,
            token: scheduleToken,
            draftSnapshot: snapshot
        )
        if let existingProfile,
           !hasProfileChanges(
            existing: existingProfile,
            session: session,
            displayName: displayNameToPublish,
            avatarURLString: avatarURLStringToPublish,
            bio: bioToPublish,
            socialLinks: socialLinksToPublish,
            publicSnapshot: publicSnapshot
           ),
           !friendScheduleChanged {
            snapshotLogger.info("📦 publishProfileNow: no profile changes, skipping CloudKit save")
            hasPendingProfileSave = false
            isPublished = true
            return
        }

        await syncStatus.withSync("儲存中...") {
            do {
                let publicRecordName = try await CloudKitProfileIdentityService.shared.ensureIdentity(for: session)
                let profile = PublicProfile(
                    cloudKitRecordName: publicRecordName,
                    userId: session.userId,
                    empNo: session.empNo,
                    displayName: displayNameToPublish,
                    avatarURLString: avatarURLStringToPublish,
                    bio: bioToPublish,
                    socialLinks: socialLinksToPublish,
                    scheduleSnapshot: publicSnapshot,
                    lastUpdated: Date()
                )

                snapshotLogger.info("☁️ publishProfileNow: sending to CloudKit — displayName=\(displayNameToPublish, privacy: .public), bio=\(profile.bio ?? "nil", privacy: .public), socialLinks=\(socialLinksToPublish.count, privacy: .public), hasSnapshot=\(profile.scheduleSnapshot != nil, privacy: .public)")
                try await CloudKitProfileService.shared.publishProfile(profile)
                if visibility == .friendsOnly, let snapshot {
                    try await CloudKitProfileService.shared.publishFriendSchedule(
                        snapshot,
                        token: scheduleToken,
                        ownerRecordName: profile.cloudKitRecordName,
                        ownerEmpNo: session.empNo
                    )
                } else if visibility == .off || visibility == .public {
                    try? await CloudKitProfileService.shared.deleteFriendSchedule(token: scheduleToken)
                }
                snapshotLogger.info("✅ publishProfileNow: CloudKit save succeeded")
                isPublished = true
                hasPendingProfileSave = false
            } catch {
                snapshotLogger.error("❌ publishProfileNow: CloudKit save failed — \(error.localizedDescription, privacy: .public)")
                if await authManager.handleProfileIdentityError(error) {
                    return
                }
                publishError = "儲存失敗：\(error.localizedDescription)"
                isPublished = false
            }
        }
    }

    private func hasFriendScheduleChanges(
        visibility: ScheduleVisibility,
        token: String,
        draftSnapshot: FriendScheduleSnapshot?
    ) async -> Bool {
        switch visibility {
        case .friendsOnly:
            guard let draftSnapshot else { return false }
            let existing = try? await CloudKitProfileService.shared.fetchFriendSchedule(token: token)
            return hasSnapshotChanges(existing, draftSnapshot)
        case .off:
            return (try? await CloudKitProfileService.shared.fetchFriendSchedule(token: token)) != nil
        case .public:
            return false
        }
    }

    private func hasProfileChanges(
        existing: PublicProfile,
        session: SISSession,
        displayName: String,
        avatarURLString: String?,
        bio: String?,
        socialLinks: [SocialLink],
        publicSnapshot: FriendScheduleSnapshot?
    ) -> Bool {
        existing.userId != session.userId ||
        existing.empNo != session.empNo ||
        existing.displayName != displayName ||
        existing.avatarURLString != avatarURLString ||
        normalizedOptionalText(existing.bio) != normalizedOptionalText(bio) ||
        existing.socialLinks != socialLinks ||
        hasSnapshotChanges(existing.scheduleSnapshot, publicSnapshot)
    }

    private func hasSnapshotChanges(_ existing: FriendScheduleSnapshot?, _ draft: FriendScheduleSnapshot?) -> Bool {
        switch (existing, draft) {
        case (.none, .none):
            return false
        case (.some(let existing), .some(let draft)):
            return existing.ownerUserId != draft.ownerUserId ||
            existing.ownerDisplayName != draft.ownerDisplayName ||
            existing.semester != draft.semester ||
            existing.courses != draft.courses
        default:
            return true
        }
    }

    private func normalizedOptionalText(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    // MARK: - Disable (delete from CloudKit)

    private func disableProfile() async {
        guard let session = sisSession else {
            isPublished = false
            return
        }
        do {
            let recordName = try await CloudKitProfileIdentityService.shared.ensureIdentity(for: session)
            try await CloudKitProfileService.shared.deleteProfile(recordName: recordName)
        } catch {
            if await authManager.handleProfileIdentityError(error) {
                return
            }
            // Silently ignore delete errors (record may not exist)
        }
        try? await CloudKitProfileService.shared.deleteFriendSchedule(token: ProfileQRService.scheduleShareToken())
        isPublished = false
    }

    // MARK: - Schedule Snapshot

    private let snapshotLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.nelsongx.apps.fju-aio", category: "ScheduleSnapshot")

    private func buildSnapshot(session: SISSession) async -> FriendScheduleSnapshot? {
        let cache = AppCache.shared

        let semesters: [String]
        if let cached = cache.getSemesters(), !cached.isEmpty {
            semesters = cached
            snapshotLogger.info("📅 buildSnapshot: cached semesters = \(cached.description, privacy: .public)")
        } else if let fetched = try? await service.fetchAvailableSemesters(), !fetched.isEmpty {
            semesters = fetched
            cache.setSemesters(fetched)
            snapshotLogger.info("📅 buildSnapshot: fetched semesters = \(fetched.description, privacy: .public)")
        } else {
            snapshotLogger.warning("⚠️ buildSnapshot: no semesters available — snapshot will be nil")
            return nil
        }

        let semester = semesters[0]
        let courses: [Course]
        if let cached = cache.getCourses(semester: semester), !cached.isEmpty {
            courses = cached
            snapshotLogger.info("📚 buildSnapshot: semester=\(semester, privacy: .public), cached courses count = \(cached.count, privacy: .public)")
        } else if let fetched = try? await service.fetchCourses(semester: semester), !fetched.isEmpty {
            courses = fetched
            cache.setCourses(fetched, semester: semester)
            snapshotLogger.info("📚 buildSnapshot: semester=\(semester, privacy: .public), fetched courses count = \(fetched.count, privacy: .public)")
        } else {
            snapshotLogger.warning("⚠️ buildSnapshot: no courses for semester \(semester, privacy: .public) — snapshot will be nil")
            return nil
        }


        let publicCourses = courses.map { PublicCourseInfo(from: $0) }
        snapshotLogger.info("✅ buildSnapshot: building snapshot with \(publicCourses.count, privacy: .public) courses for semester \(semester, privacy: .public)")
        for c in publicCourses {
            snapshotLogger.debug("  📖 \(c.name, privacy: .public) day=\(c.dayOfWeek, privacy: .public) periods=\(c.startPeriod, privacy: .public)-\(c.endPeriod, privacy: .public)")
        }

        return FriendScheduleSnapshot(
            ownerUserId: session.userId,
            ownerDisplayName: session.userName,
            semester: semester,
            courses: publicCourses,
            updatedAt: Date()
        )
    }

    private var previewProfile: PublicProfile? {
        guard let session = sisSession else { return nil }
        return PublicProfile(
            cloudKitRecordName: ProfileIdentity.publicRecordName(for: session),
            userId: session.userId,
            empNo: session.empNo,
            displayName: displayName.isEmpty ? session.userName : displayName,
            avatarURLString: profileAvatarURL?.absoluteString,
            bio: bio.isEmpty ? nil : bio,
            socialLinks: socialLinks,
            scheduleSnapshot: scheduleVisibility == .public ? buildCachedSnapshot(session: session) : nil,
            lastUpdated: Date()
        )
    }

    private func hasStoredProfileValue(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) != nil
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

    private func buildCachedSnapshot(session: SISSession) -> FriendScheduleSnapshot? {
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
