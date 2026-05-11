import SwiftUI

struct AssignmentsView: View {
    @Environment(\.fjuService) private var service
    @State private var assignments: [Assignment] = []
    @State private var isLoading = true
    @State private var isBulkAdding = false
    @State private var bulkAddResult: BulkAddResult?
    @State private var reminderAccessDenied = false
    @AppStorage(EventKitSyncService.autoSyncTodoKey) private var autoSyncTodo = false

    private let cache = AppCache.shared

    private var displayedAssignments: [Assignment] {
        assignments.sorted { $0.dueDate < $1.dueDate }
    }

    private var overdueCount: Int {
        assignments.filter { $0.dueDate < Date() }.count
    }

    var body: some View {
        List {
            // Overdue warning
            if overdueCount > 0 {
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text("有 \(overdueCount) 項作業已過期")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                }
            }

            // Assignment list
            Section {
                if displayedAssignments.isEmpty {
                    Text("沒有待完成的作業")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(displayedAssignments) { assignment in
                        AssignmentRow(assignment: assignment)
                    }
                }
            }
        }
        .adaptiveListContentMargins()
        .navigationTitle("作業 Todo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isBulkAdding {
                    ProgressView()
                } else if !displayedAssignments.isEmpty {
                    Button {
                        bulkAddToTodo()
                    } label: {
                        Label("全部加入待辦", systemImage: "checklist.checked")
                    }
                }
            }
        }
        .overlay {
            if isLoading {
                ProgressView("載入中...")
            }
        }
        .alert("無法存取提醒事項", isPresented: $reminderAccessDenied) {
            Button("取消", role: .cancel) {}
            Button("前往設定") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text("請在「設定」中允許存取提醒事項。")
        }
        .alert(
            bulkAddResult?.title ?? "",
            isPresented: Binding(
                get: { bulkAddResult != nil },
                set: { if !$0 { bulkAddResult = nil } }
            )
        ) {
            Button("確定", role: .cancel) { bulkAddResult = nil }
        } message: {
            Text(bulkAddResult?.message ?? "")
        }
        .task {
            await loadAssignments(forceRefresh: false)
        }
        .refreshable {
            await loadAssignments(forceRefresh: true)
        }
    }

    private func bulkAddToTodo() {
        Task {
            do {
                await MainActor.run { isBulkAdding = true }
                let summary = try await EventKitSyncService.shared.syncAssignments(displayedAssignments)

                await MainActor.run {
                    isBulkAdding = false
                    var message = "已加入「\(summary.targetName)」\(summary.added) 個待辦。"
                    if summary.skipped > 0 { message += "\n略過 \(summary.skipped) 個重複待辦。" }
                    bulkAddResult = BulkAddResult(title: "加入完成", message: message)
                }
            } catch EventKitSyncService.SyncError.reminderAccessDenied {
                await MainActor.run {
                    isBulkAdding = false
                    reminderAccessDenied = true
                }
            } catch {
                await MainActor.run {
                    isBulkAdding = false
                    bulkAddResult = BulkAddResult(title: "加入失敗", message: error.localizedDescription)
                }
            }
        }
    }

    private struct BulkAddResult {
        let title: String
        let message: String
    }

    private func loadAssignments(forceRefresh: Bool) async {
        let cachedAssignments = cache.getAssignments()
        if let cached = cachedAssignments, (!forceRefresh || assignments.isEmpty) {
            assignments = cached
            isLoading = false
            WidgetDataWriter.shared.writeAssignmentData(assignments: cached)
            await autoSyncIfNeeded(cached)
            if !forceRefresh { return }
        }

        isLoading = assignments.isEmpty
        do {
            let fetched = try await service.fetchAssignments()
            assignments = fetched
            cache.setAssignments(fetched)
            WidgetDataWriter.shared.writeAssignmentData(assignments: fetched)
            await autoSyncIfNeeded(fetched)
        } catch {}
        isLoading = false
    }

    private func autoSyncIfNeeded(_ assignments: [Assignment]) async {
        guard autoSyncTodo else { return }
        do {
            try await EventKitSyncService.shared.syncAssignments(assignments)
        } catch EventKitSyncService.SyncError.reminderAccessDenied {
            EventKitSyncService.shared.disableAutoTodoSyncForPermissionIssue()
            autoSyncTodo = false
            reminderAccessDenied = true
        } catch {}
    }
}
