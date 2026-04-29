import SwiftUI

struct AllFunctionsView: View {
    @Environment(\.openURL) private var openURL
    @AppStorage(ModuleRegistry.checkInFeatureEnabledKey) private var checkInEnabled = false
    @AppStorage("openLinksInApp") private var openLinksInApp = true
    @State private var showBrowser = false
    @State private var browserURL: URL? = nil
    @State private var showDormBrowser = false

    private static let dormHost = "dorm.fju.edu.tw"

    var body: some View {
        List {
            ForEach(ModuleRegistry.groupedByCategory(checkInEnabled: checkInEnabled), id: \.0) { category, modules in
                Section(category.rawValue) {
                    ForEach(modules) { module in
                        moduleRow(module)
                    }
                }
            }
        }
        .navigationTitle("全部功能")
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
                .foregroundStyle(module.color)
                .frame(width: 32)
            Text(module.name)
                .foregroundStyle(.primary)
        }
    }
}
