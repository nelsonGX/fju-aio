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

                                    Image(systemName: preferences.isSelected(module.id)
                                          ? "checkmark.circle.fill"
                                          : "circle")
                                        .foregroundStyle(
                                            preferences.isSelected(module.id)
                                            ? Color.accentColor : .gray
                                        )
                                        .font(.title3)
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
}
