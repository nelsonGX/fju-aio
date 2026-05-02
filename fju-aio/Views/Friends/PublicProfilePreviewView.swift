import SwiftUI

struct PublicProfilePreviewView: View {
    let profile: PublicProfile
    var avatarURL: URL? = nil

    var body: some View {
        List {
            PublicProfileHeaderSection(profile: profile, avatarURL: avatarURL ?? profile.avatarURL)
            PublicProfileInfoSections(profile: profile)
        }
        .listStyle(.insetGrouped)
        .navigationTitle("公開資料預覽")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PublicProfileInfoSections: View {
    let profile: PublicProfile

    var body: some View {
        if let bio = profile.bio, !bio.isEmpty {
            Section("自我介紹") {
                Text(bio)
                    .font(.subheadline)
            }
        }

        if !profile.socialLinks.isEmpty {
            Section("社群連結") {
                ForEach(profile.socialLinks) { link in
                    PublicProfileSocialLinkRow(link: link)
                }
            }
        }

        if let snapshot = profile.scheduleSnapshot, !snapshot.courses.isEmpty {
            Section("公開課表") {
                NavigationLink {
                    PublicProfileScheduleView(snapshot: snapshot)
                } label: {
                    Label("\(snapshot.courses.count) 門課", systemImage: "calendar")
                }
            }
        }
    }
}

private struct PublicProfileHeaderSection: View {
    let profile: PublicProfile
    let avatarURL: URL?
    @State private var showAvatarMessage = false

    var body: some View {
        Section {
            HStack {
                Spacer()
                VStack(spacing: 10) {
                    ProfileAvatarView(name: profile.displayName, avatarURL: avatarURL, size: 82)
                        .onTapGesture { showAvatarMessage = true }

                    Text(profile.displayName)
                        .font(.title3.weight(.semibold))
                    Text(profile.empNo)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .alert("頭貼", isPresented: $showAvatarMessage) {
                Button("確定", role: .cancel) {}
            } message: {
                Text("請前往 TronClass 更改這個頭貼")
            }
        }
    }
}

struct ProfileAvatarView: View {
    let name: String
    let avatarURL: URL?
    let size: CGFloat

    var body: some View {
        AsyncImage(url: avatarURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 1.5))
            default:
                Circle()
                    .fill(AppTheme.accent.opacity(0.15))
                    .frame(width: size, height: size)
                    .overlay {
                        Text(String(name.prefix(1)))
                            .font(.system(size: size * 0.42, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                    }
                    .overlay(Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 1.5))
            }
        }
    }
}

private struct PublicProfileSocialLinkRow: View {
    let link: SocialLink

    var body: some View {
        let content = HStack(spacing: 12) {
            SocialBrandIcon(platform: link.platform)

            VStack(alignment: .leading, spacing: 2) {
                Text(link.platform.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(link.displayHandle)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
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

struct PublicProfileScheduleView: View {
    let snapshot: FriendScheduleSnapshot

    var body: some View {
        List {
            Section {
                LabeledContent("姓名", value: snapshot.ownerDisplayName)
                LabeledContent("學期", value: snapshot.semester)
                LabeledContent("更新時間", value: snapshot.updatedAt.formatted(date: .abbreviated, time: .shortened))
            }

            Section("課表") {
                ForEach(snapshot.courses) { course in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(course.name)
                            .font(.subheadline.weight(.medium))
                        Text("\(course.dayOfWeek) 第 \(course.startPeriod)-\(course.endPeriod) 節")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !course.location.isEmpty {
                            Text(course.location)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("公開課表")
        .navigationBarTitleDisplayMode(.inline)
    }
}
