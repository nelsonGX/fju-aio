import SwiftUI

struct SearchResultsView: View {
    let results: [SearchResult]
    @Binding var browserURL: URL?
    @Binding var showBrowser: Bool
    @Binding var showDormBrowser: Bool
    @Environment(\.openURL) private var openURL
    @AppStorage("openLinksInApp") private var openLinksInApp = true

    private static let dormHost = "dorm.fju.edu.tw"

    // Group results by kind category for section display
    private var groupedResults: [(String, [SearchResult])] {
        var groups: [(label: String, priority: Int, items: [SearchResult])] = []
        var seen = Set<String>()

        func group(for kind: SearchResultKind) -> (String, Int) {
            switch kind {
            case .module:            return ("功能", 0)
            case .course:            return ("課程", 1)
            case .assignment:        return ("作業 Todo", 2)
            case .calendarEvent:     return ("行事曆", 3)
            case .classroom:         return ("教室", 4)
            case .campusBuilding,
                 .campusAmenity:     return ("校園地圖", 5)
            case .guideTopic:        return ("學生指南", 6)
            case .regulation:        return ("重要法規", 7)
            case .emergencyContact:  return ("緊急聯絡", 8)
            case .departmentContact: return ("業務單位", 9)
            }
        }

        for result in results {
            let (label, priority) = group(for: result.kind)
            if seen.insert(label).inserted {
                groups.append((label: label, priority: priority, items: []))
            }
            if let idx = groups.firstIndex(where: { $0.label == label }) {
                groups[idx].items.append(result)
            }
        }

        return groups.sorted { $0.priority < $1.priority }.map { ($0.label, $0.items) }
    }

    var body: some View {
        if results.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                Text("沒有找到相關結果")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .listRowBackground(Color.clear)
        } else {
            ForEach(groupedResults, id: \.0) { label, items in
                Section(label) {
                    ForEach(items) { result in
                        searchResultRow(result)
                    }
                }
            }
        }
    }

    // MARK: - Row Builder

    @ViewBuilder
    private func searchResultRow(_ result: SearchResult) -> some View {
        switch result.kind {
        case .module(let module):
            moduleRow(module)

        case .course(let course):
            NavigationLink(value: AppDestination.courseDetail(courseID: course.id)) {
                SearchResultLabel(
                    icon: result.icon,
                    iconColor: .blue,
                    title: result.title,
                    subtitle: result.subtitle
                )
            }

        case .classroom(let roomCode):
            ClassroomSearchRow(roomCode: roomCode)

        case .campusBuilding(let building):
            NavigationLink(value: AppDestination.campusMapLocation(location: building.code)) {
                SearchResultLabel(
                    icon: result.icon,
                    iconColor: .green,
                    title: result.title,
                    subtitle: result.subtitle
                )
            }

        case .campusAmenity(let amenity):
            NavigationLink(value: AppDestination.campusMap) {
                SearchResultLabel(
                    icon: result.icon,
                    iconColor: amenity.category == .foodCourt ? Color(red: 0.76, green: 0.25, blue: 0.05) : Color(red: 0.06, green: 0.46, blue: 0.43),
                    title: result.title,
                    subtitle: result.subtitle
                )
            }

        case .calendarEvent:
            NavigationLink(value: AppDestination.semesterCalendar) {
                SearchResultLabel(
                    icon: result.icon,
                    iconColor: .red,
                    title: result.title,
                    subtitle: result.subtitle
                )
            }

        case .assignment:
            NavigationLink(value: AppDestination.assignments) {
                SearchResultLabel(
                    icon: result.icon,
                    iconColor: .cyan,
                    title: result.title,
                    subtitle: result.subtitle
                )
            }

        case .guideTopic(let topic):
            NavigationLink {
                GuideTopicDetailView(topic: topic)
            } label: {
                SearchResultLabel(
                    icon: result.icon,
                    iconColor: .indigo,
                    title: result.title,
                    subtitle: result.subtitle
                )
            }

        case .regulation(let reg):
            if let url = reg.url {
                regulationRow(reg: reg, url: url)
            } else {
                SearchResultLabel(
                    icon: result.icon,
                    iconColor: .purple,
                    title: result.title,
                    subtitle: result.subtitle
                )
            }

        case .emergencyContact(let contact):
            EmergencyContactSearchRow(contact: contact)

        case .departmentContact(let dept):
            DepartmentContactSearchRow(dept: dept)
        }
    }

    // MARK: - Module Row (mirrors AllFunctionsView)

    @ViewBuilder
    private func moduleRow(_ module: AppModule) -> some View {
        switch module.type {
        case .inApp(let destination):
            NavigationLink(value: destination) {
                SearchResultLabel(
                    icon: module.icon,
                    iconColor: AppTheme.accent,
                    title: module.name,
                    subtitle: module.category.rawValue
                )
            }
        case .webLink(let url):
            if url.host == Self.dormHost {
                Button {
                    showDormBrowser = true
                } label: {
                    webLinkLabel(module: module)
                }
            } else if openLinksInApp && (url.scheme == "https" || url.scheme == "http") {
                Button {
                    browserURL = url
                    showBrowser = true
                } label: {
                    webLinkLabel(module: module)
                }
            } else {
                Button {
                    openURL(url)
                } label: {
                    webLinkLabel(module: module)
                }
            }
        }
    }

    private func webLinkLabel(module: AppModule) -> some View {
        HStack {
            SearchResultLabel(
                icon: module.icon,
                iconColor: AppTheme.accent,
                title: module.name,
                subtitle: module.category.rawValue
            )
            Spacer()
            Image(systemName: "globe")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Regulation Row

    @ViewBuilder
    private func regulationRow(reg: Regulation, url: URL) -> some View {
        if openLinksInApp {
            Button {
                browserURL = url
                showBrowser = true
            } label: {
                HStack {
                    SearchResultLabel(
                        icon: "doc.text.magnifyingglass",
                        iconColor: .purple,
                        title: reg.title,
                        subtitle: reg.office.rawValue
                    )
                    Spacer()
                    Image(systemName: "globe")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        } else {
            Button {
                openURL(url)
            } label: {
                HStack {
                    SearchResultLabel(
                        icon: "doc.text.magnifyingglass",
                        iconColor: .purple,
                        title: reg.title,
                        subtitle: reg.office.rawValue
                    )
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

// MARK: - Classroom Row

private struct ClassroomSearchRow: View {
    let roomCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: "door.left.hand.open")
                    .font(.title3)
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 32)
                Text(roomCode)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            HStack(spacing: 8) {
                NavigationLink(value: AppDestination.classroomSchedule) {
                    Label("課表", systemImage: "list.bullet.rectangle")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AppTheme.accent.opacity(0.12), in: Capsule())
                        .foregroundStyle(AppTheme.accent)
                }
                .buttonStyle(.plain)

                NavigationLink(value: AppDestination.campusMapLocation(location: roomCode)) {
                    Label("地圖", systemImage: "map.fill")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.green.opacity(0.12), in: Capsule())
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 44)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Emergency Contact Row

private struct EmergencyContactSearchRow: View {
    let contact: EmergencyContact

    private var callURL: URL? {
        let digits = contact.phone.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty else { return nil }
        return URL(string: "tel:\(digits)")
    }

    var body: some View {
        HStack {
            SearchResultLabel(
                icon: "phone.fill",
                iconColor: .green,
                title: contact.name,
                subtitle: contact.phone
            )
            Spacer()
            if let url = callURL {
                Link(destination: url) {
                    Image(systemName: "phone.fill")
                        .font(.subheadline)
                        .frame(width: 36, height: 36)
                        .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(.green)
                }
            }
        }
    }
}

// MARK: - Department Contact Row

private struct DepartmentContactSearchRow: View {
    let dept: DepartmentContact

    private var primaryPhone: URL? {
        guard let first = dept.phones.first else { return nil }
        let base = first.components(separatedBy: " (").first ?? first
        let digits = base.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty else { return nil }
        return URL(string: "tel:\(digits)")
    }

    private var mailURL: URL? {
        guard let email = dept.email else { return nil }
        return URL(string: "mailto:\(email)")
    }

    var body: some View {
        HStack(spacing: 12) {
            SearchResultLabel(
                icon: "building.2.fill",
                iconColor: .teal,
                title: dept.name,
                subtitle: dept.phones.first ?? (dept.email ?? "")
            )
            Spacer()
            HStack(spacing: 8) {
                if let url = primaryPhone {
                    Link(destination: url) {
                        Image(systemName: "phone.fill")
                            .font(.subheadline)
                            .frame(width: 36, height: 36)
                            .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(.green)
                    }
                }
                if let url = mailURL {
                    Link(destination: url) {
                        Image(systemName: "envelope.fill")
                            .font(.subheadline)
                            .frame(width: 36, height: 36)
                            .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(.blue)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared Label

struct SearchResultLabel: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}
