import SwiftUI

struct AttendanceView: View {
    @Environment(\.fjuService) private var service
    @State private var records: [AttendanceRecord] = []
    @State private var isLoading = true
    @State private var selectedCourse = "全部"

    private let semester = "113-2"
    private let cache = AppCache.shared

    private var courseNames: [String] {
        let names = Set(records.map(\.courseName))
        return ["全部"] + names.sorted()
    }

    private var filteredRecords: [AttendanceRecord] {
        let filtered = selectedCourse == "全部" ? records : records.filter { $0.courseName == selectedCourse }
        return filtered.sorted { $0.date > $1.date }
    }

    private var summary: (total: Int, present: Int, absent: Int, late: Int, excused: Int) {
        let r = filteredRecords
        return (
            r.count,
            r.filter { $0.status == .present }.count,
            r.filter { $0.status == .absent }.count,
            r.filter { $0.status == .late }.count,
            r.filter { $0.status == .excused }.count
        )
    }

    var body: some View {
        List {
            // Summary card
            Section {
                summaryCard
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            // Filter
            Section {
                Picker("課程篩選", selection: $selectedCourse) {
                    ForEach(courseNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
            }

            // Records
            Section("出缺席紀錄") {
                if filteredRecords.isEmpty {
                    Text("無紀錄")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredRecords) { record in
                        AttendanceRow(record: record)
                    }
                }
            }
        }
        .adaptiveListContentMargins()
        .navigationTitle("出缺席查詢")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isLoading {
                ProgressView("載入中...")
            }
        }
        .task {
            await loadRecords(forceRefresh: false)
        }
        .refreshable {
            await loadRecords(forceRefresh: true)
        }
    }

    private func loadRecords(forceRefresh: Bool) async {
        if !forceRefresh, let cached = cache.getAttendance(semester: semester) {
            records = cached
            isLoading = false
            return
        }

        isLoading = true
        do {
            let fetched = try await service.fetchAttendanceRecords(semester: semester)
            records = fetched
            cache.setAttendance(fetched, semester: semester)
        } catch {}
        isLoading = false
    }

    private var summaryCard: some View {
        HStack {
            summaryItem(label: "出席", count: summary.present, color: .green)
            Spacer()
            summaryItem(label: "缺席", count: summary.absent, color: .red)
            Spacer()
            summaryItem(label: "遲到", count: summary.late, color: .orange)
            Spacer()
            summaryItem(label: "請假", count: summary.excused, color: .blue)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func summaryItem(label: String, count: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.title2.weight(.bold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
