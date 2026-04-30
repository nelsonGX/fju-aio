import SwiftUI

struct HomeEditView: View {
    @Environment(HomePreferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ModuleRegistry.checkInFeatureEnabledKey) private var checkInEnabled = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(ModuleRegistry.groupedByCategory(checkInEnabled: checkInEnabled), id: \.0) { category, modules in
                    Section(category.rawValue) {
                        ForEach(modules) { module in
                            Button {
                                withAnimation { preferences.toggle(module.id) }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: module.icon)
                                        .font(.title3)
                                        .foregroundStyle(module.color)
                                        .frame(width: 32)

                                    Text(module.name)
                                        .foregroundStyle(.primary)

                                    Spacer()

                                    selectionIndicator(for: module)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("編輯首頁")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("重設") {
                        preferences.resetToDefaults()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func selectionIndicator(for module: AppModule) -> some View {
        if let index = preferences.selectedModuleIDs.firstIndex(of: module.id) {
            Text("\(index + 1)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(AppTheme.accent, in: Circle())
                .accessibilityLabel("已選擇，第 \(index + 1) 個")
        } else {
            Image(systemName: "circle")
                .font(.title3)
                .foregroundStyle(.gray)
                .accessibilityLabel("未選擇")
        }
    }
}
