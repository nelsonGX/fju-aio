import SwiftUI

// MARK: - Feature Item Model

private struct FeatureItem: Identifiable {
    let id = UUID()
    let icon: String
    let color: Color
    let title: String
    let description: String
}

// MARK: - Onboarding Page Model

private enum OnboardingPage: Int, CaseIterable {
    case welcome
    case features
    case settings

    var totalCount: Int { OnboardingPage.allCases.count }
}

// MARK: - Onboarding View

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("preferredMapsApp") private var preferredMapsApp = "apple"
    @State private var currentPage: OnboardingPage = .welcome

    private let notificationManager = CourseNotificationManager.shared
    private let syncStatus = SyncStatusManager.shared

    private let features: [FeatureItem] = [
        FeatureItem(icon: "calendar", color: .blue,
                    title: "課表查詢",
                    description: "快速查看本週課程安排，支援即時動態島課程提醒"),
        FeatureItem(icon: "chart.bar.fill", color: .green,
                    title: "成績查詢",
                    description: "查看學期成績與 GPA 統計，追蹤學業表現"),
        FeatureItem(icon: "doc.text.fill", color: .purple,
                    title: "請假申請",
                    description: "直接在 App 內提交請假申請，省去登入網頁的麻煩"),
        FeatureItem(icon: "checkmark.circle.fill", color: .teal,
                    title: "出缺席查詢",
                    description: "一目瞭然地查看所有課程的出缺席紀錄"),
        FeatureItem(icon: "checklist", color: .indigo,
                    title: "作業 Todo",
                    description: "整合 TronClass 作業截止日期，不再錯過任何繳交期限"),
        FeatureItem(icon: "calendar.badge.clock", color: .red,
                    title: "學期行事曆",
                    description: "查看學校重要日程，包含考試週、補假與校慶等活動"),
        FeatureItem(icon: "doc.richtext.fill", color: .orange,
                    title: "在學證明",
                    description: "隨時下載在學證明 PDF，申辦各種手續更方便"),
        FeatureItem(icon: "map.fill", color: .green,
                    title: "校園地圖",
                    description: "找到校園內每棟建築的位置，輕鬆導航"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                welcomePage
                    .tag(OnboardingPage.welcome)

                featuresPage
                    .tag(OnboardingPage.features)

                settingsPage
                    .tag(OnboardingPage.settings)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: currentPage)

            bottomBar
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Page 1: Welcome

    private var welcomePage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "graduationcap.fill")
                .font(.system(size: 80))
                .foregroundStyle(.blue)

            VStack(spacing: 12) {
                Text("歡迎使用輔大 All In One")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)

                Text("一個 App，整合所有輔大校務服務")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(spacing: 16) {
                highlightCard(icon: "bolt.fill", color: .yellow, title: "快速存取", description: "所有功能集中一處，隨時查閱")
                highlightCard(icon: "lock.shield.fill", color: .blue, title: "安全登入", description: "使用學校 LDAP 統一帳號，資料加密儲存")
                highlightCard(icon: "bell.badge.fill", color: .red, title: "智慧通知", description: "上課前動態島提醒，不再遲到")
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .padding(.horizontal, 8)
    }

    private func highlightCard(icon: String, color: Color, title: String, description: String) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Page 2: Features

    private var featuresPage: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Text("主要功能")
                        .font(.largeTitle.bold())
                    Text("輔大 AIO 提供以下功能")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 40)
                .padding(.bottom, 24)

                VStack(spacing: 0) {
                    ForEach(Array(features.enumerated()), id: \.element.id) { index, feature in
                        FeatureRow(item: feature)
                        if index < features.count - 1 {
                            Divider()
                                .padding(.leading, 60)
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Page 3: Settings

    private var settingsPage: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Text("初始設定")
                        .font(.largeTitle.bold())
                    Text("依照您的偏好設定功能")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 40)
                .padding(.bottom, 24)

                VStack(spacing: 0) {
                    // Course notifications toggle
                    Toggle(isOn: Binding(
                        get: { notificationManager.isEnabled },
                        set: { notificationManager.isEnabled = $0 }
                    )) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("課程提醒通知")
                                    .font(.body)
                                Text("上課前透過靈動島提醒您")
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

                    Divider()
                        .padding(.leading, 60)

                    // Sync status bar toggle
                    Toggle(isOn: Binding(
                        get: { syncStatus.isEnabled },
                        set: { syncStatus.isEnabled = $0 }
                    )) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("顯示同步狀態列")
                                    .font(.body)
                                Text("資料同步時在頂部顯示進度")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundStyle(.blue)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    Divider()
                        .padding(.leading, 60)

                    // Maps app picker
                    VStack(alignment: .leading, spacing: 8) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("預設導航應用程式")
                                    .font(.body)
                                Text("用於校園地圖的導航功能")
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
                }
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)

                Text("這些設定之後可以在「設定」頁面隨時更改。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 32)
                    .padding(.top, 8)
            }
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 16) {
            // Page indicator dots
            HStack(spacing: 8) {
                ForEach(OnboardingPage.allCases, id: \.rawValue) { page in
                    Capsule()
                        .fill(currentPage == page ? Color.blue : Color.secondary.opacity(0.3))
                        .frame(width: currentPage == page ? 20 : 8, height: 8)
                        .animation(.spring(response: 0.3), value: currentPage)
                }
            }

            // Action button
            Button {
                if currentPage == .settings {
                    hasCompletedOnboarding = true
                } else {
                    withAnimation {
                        currentPage = OnboardingPage(rawValue: currentPage.rawValue + 1) ?? .settings
                    }
                }
            } label: {
                Text(currentPage == .settings ? "開始使用" : "繼續")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .contentShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)

            // Skip button on non-last pages
            if currentPage != .settings {
                Button("跳過") {
                    hasCompletedOnboarding = true
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            } else {
                // Placeholder to keep layout stable
                Color.clear.frame(height: 20)
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 32)
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Feature Row

private struct FeatureRow: View {
    let item: FeatureItem

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(item.color)
                    .frame(width: 34, height: 34)
                Image(systemName: item.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body)
                Text(item.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

#Preview {
    OnboardingView()
}
