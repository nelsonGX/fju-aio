import SwiftUI

private struct RegulationBrowserItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct RegulationsView: View {
    @State private var searchText = ""
    @State private var browserItem: RegulationBrowserItem?
    @State private var showMissingURLAlert = false

    private var filteredRegulations: [Regulation] {
        RegulationIndex.filtered(by: searchText)
    }

    private var groupedRegulations: [(RegulationOffice, [Regulation])] {
        let grouped = Dictionary(grouping: filteredRegulations, by: \.office)
        return RegulationOffice.allCases.compactMap { office in
            guard let regulations = grouped[office] else { return nil }
            return (office, regulations)
        }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("收錄校內常用法規標題、承辦單位與來源連結。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("內容與修正日期仍以各單位公告頁面或 PDF 為準。")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            }

            ForEach(groupedRegulations, id: \.0) { office, regulations in
                Section(office.rawValue) {
                    ForEach(regulations) { regulation in
                        Button {
                            if let url = regulation.url {
                                browserItem = RegulationBrowserItem(url: url)
                            } else {
                                showMissingURLAlert = true
                            }
                        } label: {
                            RegulationRow(regulation: regulation)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .adaptiveListContentMargins()
        .navigationTitle("重要法規")
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "搜尋選課、獎學金、宿舍、網路..."
        )
        .sheet(item: $browserItem) { item in
            InAppBrowserView(url: item.url)
                .ignoresSafeArea()
        }
        .alert("無法開啟連結", isPresented: $showMissingURLAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text("這筆法規在原始清單中沒有有效網址。")
        }
    }
}

private struct RegulationRow: View {
    let regulation: Regulation

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.title3)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 34, height: 34)
                .background(AppTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(regulation.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(regulation.office.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: regulation.url == nil ? "exclamationmark.triangle" : "globe")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
