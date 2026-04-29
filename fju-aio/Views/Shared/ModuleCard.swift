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
        VStack(spacing: 12) {
            Image(systemName: module.icon)
                .font(.system(size: 28))
                .foregroundStyle(module.color)
            Text(module.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
