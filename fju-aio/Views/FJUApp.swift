import SwiftUI

enum AppStartupSettings {
    static let syncDuringSplashKey = "startup.syncDuringSplash"
}

@main
struct FJUApp: App {
    @State private var authManager = AuthenticationManager()
    @State private var isPreloading = false
    @State private var isCompletingOnboarding = false
    @State private var hasSkippedPreload = false
    @State private var showsSkipPreloadButton = false
    @State private var isWidgetQuickLaunch = false
    @State private var pendingDeepLinkDestination: AppDestination?
    @State private var preloadStatusText = "檢查登入狀態..."
    @State private var onboardingStatusText = "準備完成設定..."
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage(AppStartupSettings.syncDuringSplashKey) private var syncDuringSplash = true
    private let syncStatus = SyncStatusManager.shared

    init() {
        _ = CourseNotificationManager.shared
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if authManager.isCheckingAuth && !isWidgetQuickLaunch {
                    LaunchScreenView(
                        titleText: "啟動中...",
                        statusText: "檢查登入狀態...",
                        showsSkipButton: false,
                        onSkip: {},
                        isPreloading: false
                    )
                } else if authManager.isAuthenticated && authManager.isLoading {
                    LaunchScreenView(
                        titleText: "登出中...",
                        statusText: "清除本機、CloudKit 與快取資料...",
                        showsSkipButton: false,
                        onSkip: {},
                        isPreloading: false
                    )
                } else if isCompletingOnboarding {
                    LaunchScreenView(
                        titleText: "準備使用...",
                        statusText: onboardingStatusText,
                        showsSkipButton: false,
                        onSkip: {},
                        isPreloading: false
                    )
                } else if isPreloading && !hasSkippedPreload && !isWidgetQuickLaunch {
                    LaunchScreenView(
                        titleText: "同步資料中...",
                        statusText: preloadStatusText,
                        showsSkipButton: showsSkipPreloadButton,
                        onSkip: skipPreload,
                        isPreloading: true
                    )
                } else if authManager.isAuthenticated || (authManager.isCheckingAuth && isWidgetQuickLaunch) {
                    if hasCompletedOnboarding {
                        ContentView(pendingDeepLinkDestination: $pendingDeepLinkDestination)
                            .environment(\.fjuService, FJUService.shared)
                            .environment(HomePreferences())
                            .environment(authManager)
                            .environment(syncStatus)
                    } else {
                        OnboardingView(onComplete: beginOnboardingCompletionSplash)
                            .environment(authManager)
                            .environment(syncStatus)
                    }
                } else {
                    LoginView()
                        .environment(authManager)
                }
            }
            .tint(AppTheme.accent)
            .onOpenURL { url in
                handleDeepLink(url)
            }
            .onChange(of: authManager.isCheckingAuth) { _, stillChecking in
                // Auth check just finished and user is logged in — preload home data
                guard !stillChecking,
                      authManager.isAuthenticated,
                      hasCompletedOnboarding,
                      !isWidgetQuickLaunch,
                      syncDuringSplash else { return }
                Task { await preloadHomeData() }
            }
            .onChange(of: hasCompletedOnboarding) { _, completed in
                guard completed,
                      authManager.isAuthenticated,
                      !isCompletingOnboarding,
                      !isPreloading else { return }
                beginOnboardingCompletionSplash()
            }
        }
    }

    @MainActor
    private func handleDeepLink(_ url: URL) {
        guard let destination = AppDestination(deepLinkURL: url) else { return }

        isWidgetQuickLaunch = true
        hasSkippedPreload = true
        showsSkipPreloadButton = false
        pendingDeepLinkDestination = destination
    }

    @MainActor
    private func beginOnboardingCompletionSplash() {
        guard !isCompletingOnboarding else { return }
        isCompletingOnboarding = true
        onboardingStatusText = "準備完成設定..."
        Task { await finishOnboardingSetup() }
    }

    @MainActor
    private func finishOnboardingSetup() async {
        defer {
            isCompletingOnboarding = false
            onboardingStatusText = "準備完成設定..."
        }

        await publishOnboardingProfileIfNeeded()

        guard syncDuringSplash else { return }
        onboardingStatusText = "同步首頁資料..."
        await preloadHomeData()
    }

    /// Fetch courses and calendar events into AppCache while the splash is still showing.
    @MainActor
    private func preloadHomeData() async {
        let service = FJUService.shared
        let cache = AppCache.shared

        // Skip if already cached from a previous session (cache is in-memory so this
        // only applies within the same process lifetime, e.g. returning from background).
        if let cached = cache.getSemesters(), !cached.isEmpty { return }

        isPreloading = true
        hasSkippedPreload = false
        showsSkipPreloadButton = false
        preloadStatusText = "準備同步資料..."
        scheduleSkipPreloadButton()
        defer {
            isPreloading = false
            showsSkipPreloadButton = false
            preloadStatusText = "同步資料中..."
        }

        do {
            preloadStatusText = "取得學期資料..."
            let semesters = try await service.fetchAvailableSemesters()
            cache.setSemesters(semesters)

            if let current = semesters.first {
                preloadStatusText = "同步課程與行事曆..."
                async let courses = service.fetchCourses(semester: current)
                async let events = service.fetchCalendarEvents(semester: current)
                let (c, e) = try await (courses, events)
                preloadStatusText = "更新小工具資料..."
                cache.setCourses(c, semester: current)
                cache.setCalendarEvents(e, semester: current)
                WidgetDataWriter.shared.writeCourseData(courses: c, friends: FriendStore.shared.friends)
                let notificationWindow = SemesterCalendarResolver.notificationWindow(
                    for: current,
                    events: e
                )
                preloadStatusText = "同步 Live Activity 伺服器..."
                await CourseNotificationManager.shared.scheduleAll(
                    for: c,
                    semesterStartDate: notificationWindow.startDate,
                    semesterEndDate: notificationWindow.endDate
                )
                if EventKitSyncService.shared.isAutoCalendarSyncEnabled {
                    preloadStatusText = "同步系統行事曆..."
                    do {
                        try await EventKitSyncService.shared.syncCalendarEvents(e)
                    } catch EventKitSyncService.SyncError.calendarAccessDenied {
                        EventKitSyncService.shared.disableAutoCalendarSyncForPermissionIssue()
                    } catch {}
                }
                if EventKitSyncService.shared.isAutoTodoSyncEnabled {
                    Task { await preloadTodoSyncIfNeeded() }
                }
            }
        } catch {
            // Non-fatal — HomeView will fetch on its own if cache is empty
        }
    }

    @MainActor
    private func preloadTodoSyncIfNeeded() async {
        do {
            let assignments = try await FJUService.shared.fetchAssignments()
            AppCache.shared.setAssignments(assignments)
            WidgetDataWriter.shared.writeAssignmentData(assignments: assignments)
            try await EventKitSyncService.shared.syncAssignments(assignments)
        } catch EventKitSyncService.SyncError.reminderAccessDenied {
            EventKitSyncService.shared.disableAutoTodoSyncForPermissionIssue()
        } catch {
            // Non-fatal — AssignmentsView will fetch and sync on its own.
        }
    }

    @MainActor
    private func publishOnboardingProfileIfNeeded() async {
        guard UserDefaults.standard.bool(forKey: "myProfile.isPublished"),
              let session = try? await authManager.getValidSISSession() else { return }

        onboardingStatusText = "準備公開個人檔案..."

        let displayName = UserDefaults.standard.string(forKey: "myProfile.displayName") ?? ""
        let bio = UserDefaults.standard.string(forKey: "myProfile.bio") ?? ""
        let shareSchedule = UserDefaults.standard.bool(forKey: "myProfile.shareSchedule")
        let scheduleVisibilityRaw = UserDefaults.standard.string(forKey: "myProfile.scheduleVisibility")
        let visibility = ScheduleVisibility(rawValue: scheduleVisibilityRaw ?? "") ?? (shareSchedule ? .public : .friendsOnly)
        let socialLinks = loadOnboardingSocialLinks()

        onboardingStatusText = "取得個人頭貼..."
        let avatarURLString = try? await TronClassAPIService.shared.getCurrentUserAvatarURL()

        onboardingStatusText = "建立課表分享資料..."
        let snapshot = visibility == .off ? nil : await buildOnboardingScheduleSnapshot(session: session)
        let profile = PublicProfile(
            cloudKitRecordName: ProfileQRService.stableDeviceToken(),
            userId: session.userId,
            empNo: session.empNo,
            displayName: displayName.isEmpty ? session.userName : displayName,
            avatarURLString: avatarURLString,
            bio: bio.isEmpty ? nil : bio,
            socialLinks: socialLinks,
            scheduleSnapshot: visibility == .public ? snapshot : nil,
            lastUpdated: Date()
        )

        onboardingStatusText = "儲存公開個人檔案..."
        do {
            try await CloudKitProfileService.shared.publishProfile(profile)
            let scheduleToken = ProfileQRService.scheduleShareToken()
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
        } catch {
            onboardingStatusText = "公開資料稍後可在好友頁重試"
            UserDefaults.standard.set(false, forKey: "myProfile.isPublished")
            try? await Task.sleep(for: .milliseconds(700))
        }
    }

    private func loadOnboardingSocialLinks() -> [SocialLink] {
        guard let data = UserDefaults.standard.data(forKey: "myProfile.socialLinks"),
              let decoded = try? JSONDecoder().decode([SocialLink].self, from: data) else {
            return []
        }
        return decoded
    }

    @MainActor
    private func buildOnboardingScheduleSnapshot(session: SISSession) async -> FriendScheduleSnapshot? {
        let cache = AppCache.shared

        let semesters: [String]
        if let cached = cache.getSemesters(), !cached.isEmpty {
            semesters = cached
        } else if let fetched = try? await FJUService.shared.fetchAvailableSemesters(), !fetched.isEmpty {
            semesters = fetched
            cache.setSemesters(fetched)
        } else {
            return nil
        }

        let semester = semesters[0]
        let courses: [Course]
        if let cached = cache.getCourses(semester: semester), !cached.isEmpty {
            courses = cached
        } else if let fetched = try? await FJUService.shared.fetchCourses(semester: semester), !fetched.isEmpty {
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

    @MainActor
    private func scheduleSkipPreloadButton() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard isPreloading, !hasSkippedPreload else { return }
            showsSkipPreloadButton = true
        }
    }

    @MainActor
    private func skipPreload() {
        hasSkippedPreload = true
        showsSkipPreloadButton = false
    }
}

// MARK: - Launch Screen

private struct LaunchScreenView: View {
    let titleText: String
    let statusText: String
    let showsSkipButton: Bool
    let onSkip: () -> Void
    let isPreloading : Bool

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(AppTheme.accent)

                Text("輔大 All In One")
                    .font(.title2.bold())

                Text(titleText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .contentTransition(.opacity)

                LaunchProgressBar()
                    .frame(width: 184, height: 5)
                
                isPreloading ? Text("你可以在 設定 > 一般 > 啟動時先同步資料 略過這個頁面")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(3)
                : nil

                if showsSkipButton {
                    Button("略過 (稍後同步資料)") {
                        onSkip()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .padding(.top, 12)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: showsSkipButton)
        }
    }
}

private struct LaunchProgressBar: View {
    @State private var isAnimating = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let barWidth = width * 0.36

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppTheme.accent.opacity(0.18))

                Capsule()
                    .fill(AppTheme.accent)
                    .frame(width: barWidth)
                    .offset(x: isAnimating ? width : -barWidth)
            }
            .clipShape(Capsule())
        }
        .accessibilityLabel("載入中")
        .onAppear {
            withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: false)) {
                isAnimating = true
            }
        }
    }
}
