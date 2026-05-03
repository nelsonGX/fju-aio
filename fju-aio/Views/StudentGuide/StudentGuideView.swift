import SwiftUI

// guideTopics references allGuideTopics from StudentGuideTopics.swift
private let guideTopics = allGuideTopics

struct StudentGuideView: View {
    @State private var searchText = ""

    private var filteredTopics: [GuideTopic] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return guideTopics }
        return guideTopics.filter { topic in
            topic.title.localizedCaseInsensitiveContains(query) ||
            topic.category.localizedCaseInsensitiveContains(query) ||
            topic.summary.localizedCaseInsensitiveContains(query) ||
            topic.keywords.contains { $0.localizedCaseInsensitiveContains(query) } ||
            topic.steps.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private var groupedTopics: [(String, [GuideTopic])] {
        let grouped = Dictionary(grouping: filteredTopics, by: \.category)
        let categoryOrder = ["教務", "學務", "安全", "生活", "生活安全"]
        return categoryOrder.compactMap { category in
            guard let topics = grouped[category] else { return nil }
            return (category, topics)
        }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("把學生手札整理成常用流程、電話與連結。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("日期、辦法與受理窗口仍以學校公告為準。")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            }

            ForEach(groupedTopics, id: \.0) { category, topics in
                Section(category) {
                    ForEach(topics) { topic in
                        NavigationLink {
                            GuideTopicDetailView(topic: topic)
                        } label: {
                            GuideTopicRow(topic: topic)
                        }
                    }
                }
            }
        }
        .adaptiveListContentMargins()
        .navigationTitle("學生指南")
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜尋選課、就貸、兵役、租屋...")
    }
}

private struct GuideTopicRow: View {
    let topic: GuideTopic

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: topic.icon)
                .font(.title3)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 34, height: 34)
                .background(AppTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(topic.title)
                    .font(.subheadline.weight(.semibold))
                Text(topic.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 3)
    }
}

struct GuideTopicDetailView: View {
    let topic: GuideTopic

    var body: some View {
        List {
            Section {
                Label(topic.category, systemImage: topic.icon)
                    .font(.headline)
                Text(topic.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("怎麼做") {
                ForEach(Array(topic.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(AppTheme.accent, in: Circle())
                        Text(step)
                            .font(.subheadline)
                    }
                    .padding(.vertical, 2)
                }
            }

            if !topic.contacts.isEmpty {
                Section("聯絡窗口") {
                    ForEach(topic.contacts) { contact in
                        GuideContactRow(contact: contact)
                    }
                }
            }

            if !topic.links.isEmpty {
                Section("相關連結") {
                    ForEach(topic.links) { link in
                        Link(destination: link.url) {
                            HStack {
                                Text(link.title)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
        }
        .adaptiveListContentMargins()
        .navigationTitle(topic.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct GuideContactRow: View {
    let contact: GuideContact

    private var callURL: URL? {
        let digits = contact.phone.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty else { return nil }
        return URL(string: "tel:\(digits)")
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name)
                    .font(.subheadline)
                Text(contact.phone)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let callURL {
                Link(destination: callURL) {
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

#Preview {
    NavigationStack {
        StudentGuideView()
    }
}
