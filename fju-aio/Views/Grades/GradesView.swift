import SwiftUI

struct GradesView: View {
    @Environment(\.fjuService) private var service
    @Environment(SyncStatusManager.self) private var syncStatus
    @State private var grades: [Grade] = []
    @State private var gpaSummary: GPASummary?
    @State private var semesters: [String] = []
    @State private var selectedSemester = ""
    @State private var isLoading = true

    private let cache = AppCache.shared

    var body: some View {
        List {
            if let summary = gpaSummary {
                Section {
                    GPASummaryView(summary: summary)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section {
                Picker("學期", selection: $selectedSemester) {
                    ForEach(semesters, id: \.self) { semester in
                        Text(semester).tag(semester)
                    }
                }
                .pickerStyle(.segmented)
            }
            .listRowBackground(Color.clear)
            .disabled(semesters.isEmpty)

            Section("成績列表") {
                if grades.isEmpty && !isLoading {
                    Text("本學期尚無成績資料")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(grades) { grade in
                        GradeRow(grade: grade)
                    }
                }
            }

            if !grades.isEmpty {
                Section {
                    let totalCredits = grades.reduce(0) { $0 + $1.credits }
                    HStack {
                        Text("總學分數")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(totalCredits)")
                            .font(.headline)
                    }
                }
            }
        }
        .navigationTitle("成績查詢")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isLoading {
                ProgressView("載入中...")
            }
        }
        .task {
            await loadData(forceRefresh: false)
        }
        .refreshable {
            await loadData(forceRefresh: true)
        }
        .onChange(of: selectedSemester) {
            Task { await loadData(forceRefresh: false) }
        }
    }

    private func loadData(forceRefresh: Bool) async {
        // Show cached data immediately if available
        if !forceRefresh {
            if semesters.isEmpty, let cached = cache.getSemesters() {
                semesters = cached
                if !cached.contains(selectedSemester), let first = cached.first {
                    selectedSemester = first
                }
            }
            if !selectedSemester.isEmpty, let cachedGrades = cache.getGrades(semester: selectedSemester) {
                grades = cachedGrades
                gpaSummary = cache.getGPASummary(semester: selectedSemester)
                isLoading = false
                return
            }
        }

        isLoading = true
        do {
            try await syncStatus.withSync("正在載入成績…") {
                let newSemesters = try await service.fetchAvailableSemesters()
                let semesterToLoad: String
                if newSemesters.contains(selectedSemester) {
                    semesterToLoad = selectedSemester
                } else if let firstSemester = newSemesters.first {
                    semesterToLoad = firstSemester
                } else {
                    semesterToLoad = ""
                }

                guard !semesterToLoad.isEmpty else {
                    semesters = []
                    grades = []
                    gpaSummary = nil
                    cache.setSemesters([])
                    return
                }

                async let fetchedGrades = service.fetchGrades(semester: semesterToLoad)
                async let fetchedSummary = service.fetchGPASummary(semester: semesterToLoad)

                let newGrades = try await fetchedGrades
                let newSummary = try await fetchedSummary

                semesters = newSemesters
                selectedSemester = semesterToLoad
                grades = newGrades
                gpaSummary = newSummary

                cache.setSemesters(newSemesters)
                cache.setGrades(newGrades, semester: semesterToLoad)
                cache.setGPASummary(newSummary, semester: semesterToLoad)
            }
        } catch {}
        isLoading = false
    }
}
