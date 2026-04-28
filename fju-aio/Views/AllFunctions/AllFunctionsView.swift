import SwiftUI

struct AllFunctionsView: View {
    @Environment(\.openURL) private var openURL
    @AppStorage(ModuleRegistry.checkInFeatureEnabledKey) private var checkInEnabled = false

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
    }

    @ViewBuilder
    private func moduleRow(_ module: AppModule) -> some View {
        switch module.type {
        case .inApp(let destination):
            NavigationLink(value: destination) {
                moduleLabel(module)
            }
        case .webLink(let url):
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
