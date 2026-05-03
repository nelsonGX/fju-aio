import SwiftUI

struct AllFunctionsView: View {
    @Environment(\.openURL) private var openURL
    @AppStorage(ModuleRegistry.checkInFeatureEnabledKey) private var checkInEnabled = false
    @AppStorage("openLinksInApp") private var openLinksInApp = true
    @State private var showBrowser = false
    @State private var browserURL: URL? = nil
    @State private var showDormBrowser = false

    // Search state
    @State private var searchText = ""
    @State private var searchResults: [SearchResult] = []
    private let searchEngine = SearchEngine()
    // Debounce task
    @State private var searchTask: Task<Void, Never>? = nil

    private static let dormHost = "dorm.fju.edu.tw"

    var body: some View {
        List {
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Normal module list
                ForEach(ModuleRegistry.groupedByCategory(checkInEnabled: checkInEnabled), id: \.0) { category, modules in
                    Section(category.rawValue) {
                        ForEach(modules) { module in
                            moduleRow(module)
                        }
                    }
                }
            } else {
                // Search results
                SearchResultsView(
                    results: searchResults,
                    browserURL: $browserURL,
                    showBrowser: $showBrowser,
                    showDormBrowser: $showDormBrowser
                )
            }
        }
        .adaptiveListContentMargins()
        .navigationTitle("全部功能")
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "搜尋功能、課程、法規、聯絡方式..."
        )
        .onChange(of: searchText) { _, newValue in
            // Debounce: cancel previous task and schedule new one
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 150_000_000) // 150ms
                guard !Task.isCancelled else { return }
                await runSearch(query: newValue)
            }
        }
        .sheet(isPresented: $showDormBrowser) {
            DormBrowserView()
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showBrowser) {
            if let browserURL {
                InAppBrowserView(url: browserURL)
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: - Search

    @MainActor
    private func runSearch(query: String) {
        let cache = AppCache.shared
        let courses = cache.allCachedCourses()
        let assignments = cache.getAssignments() ?? []
        let calendarEvents = cache.allCachedCalendarEvents()

        searchResults = searchEngine.search(
            query: query,
            courses: courses,
            assignments: assignments,
            calendarEvents: calendarEvents,
            checkInEnabled: checkInEnabled
        )
    }

    // MARK: - Module Row

    @ViewBuilder
    private func moduleRow(_ module: AppModule) -> some View {
        switch module.type {
        case .inApp(let destination):
            NavigationLink(value: destination) {
                moduleLabel(module)
            }
        case .webLink(let url):
            if url.host == Self.dormHost {
                Button {
                    showDormBrowser = true
                } label: {
                    HStack {
                        moduleLabel(module)
                        Spacer()
                        Image(systemName: "globe")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            } else if openLinksInApp && (url.scheme == "https" || url.scheme == "http") {
                Button {
                    browserURL = url
                    showBrowser = true
                } label: {
                    HStack {
                        moduleLabel(module)
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
                        moduleLabel(module)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private func moduleLabel(_ module: AppModule) -> some View {
        HStack(spacing: 12) {
            Image(systemName: module.icon)
                .font(.title3)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 32)
            Text(module.name)
                .foregroundStyle(.primary)
        }
    }
}
