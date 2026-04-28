import SwiftUI

// MARK: - Feature Item Model

private struct FeatureItem: Identifiable {
    let id = UUID()
    let icon: String
    let color: Color
    let title: String
    let description: String
}

// MARK: - Onboarding View

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("preferredMapsApp") private var preferredMapsApp = "apple"

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
        ScrollView {
            VStack(spacing: 0) {
                headerSection
                featuresSection
                settingsSection
                getStartedButton
            }
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "graduationcap.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)
                .padding(.top, 48)

            Text("歡迎使用輔大校務系統")
                .font(.title.bold())
                .multilineTextAlignment(.center)

            Text("一個 App，整合所有輔大校務服務")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 36)
    }

    // MARK: - Features

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("主要功能")

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
        }
    }

    // MARK: - Settings

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("初始設定")

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

    // MARK: - Get Started Button

    private var getStartedButton: some View {
        Button {
            hasCompletedOnboarding = true
        } label: {
            Text("開始使用")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .padding(.horizontal, 24)
        .padding(.top, 32)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 32)
            .padding(.top, 28)
            .padding(.bottom, 8)
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
