import SwiftUI

struct ModuleCard: View {
    let module: AppModule
    @Environment(\.openURL) private var openURL
    @AppStorage("openLinksInApp") private var openLinksInApp = true
    @State private var showBrowser = false
    @State private var browserURL: URL? = nil
    @State private var showDormBrowser = false

    private static let dormHost = "dorm.fju.edu.tw"

    var body: some View {
        Group {
            switch module.type {
            case .inApp(let destination):
                NavigationLink(value: destination) {
                    cardContent
                }
            case .webLink(let url):
                Button {
                    if url.host == Self.dormHost {
                        showDormBrowser = true
                    } else if openLinksInApp && (url.scheme == "https" || url.scheme == "http") {
                        browserURL = url
                        showBrowser = true
                    } else {
                        openURL(url)
                    }
                } label: {
                    cardContent
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
        }
    }

    private var cardContent: some View {
        VStack(spacing: 7) {
            Image(systemName: module.icon)
                .font(.system(size: 20))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 38, height: 38)
                .background(AppTheme.accent.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(module.name)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 76)
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.smallCornerRadius))
    }
}
