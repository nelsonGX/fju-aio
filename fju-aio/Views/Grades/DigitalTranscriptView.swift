import SwiftUI
import PDFKit

struct DigitalTranscriptView: View {
    @State private var records: [DigitalTranscriptRecord] = []
    @State private var selectedRecord: DigitalTranscriptRecord?
    @State private var includeRanking = false

    @State private var isLoadingRecords = false
    @State private var isDownloading = false
    @State private var errorMessage: String?

    // Cache
    @State private var cachedTranscripts: [CachedTranscript] = []

    // Preview sheet
    @State private var previewData: Data?
    @State private var previewTitle: String = ""
    @State private var showPreview = false

    private let cache = TranscriptCache.shared

    var body: some View {
        Form {
            // MARK: Loading indicator
            if isLoadingRecords {
                Section {
                    HStack {
                        ProgressView()
                            .padding(.trailing, 8)
                        Text("讀取成績資料中...")
                            .foregroundStyle(.secondary)
                    }
                }
            } else if !records.isEmpty {

                // MARK: Semester picker
                Section("選擇下載學期") {
                    Picker("學期", selection: $selectedRecord) {
                        Text("請選擇").tag(Optional<DigitalTranscriptRecord>.none)
                        ForEach(records) { record in
                            VStack(alignment: .leading) {
                                Text(record.hyHtDesc)
                                if !record.paymentNote.isEmpty {
                                    Text(record.paymentNote)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .tag(Optional(record))
                        }
                    }
                }

                // MARK: Options + download button
                if let record = selectedRecord {
                    Section("下載選項") {
                        Toggle("含排名", isOn: $includeRanking)
                    }

                    let isCached = cache.exists(hy: record.hy, ht: record.ht, includeRanking: includeRanking)

                    Section {
                        if isCached {
                            Button {
                                openCached(hy: record.hy, ht: record.ht, includeRanking: includeRanking,
                                           label: cacheLabel(record: record, includeRanking: includeRanking))
                            } label: {
                                Label("預覽已快取的版本", systemImage: "doc.fill")
                            }
                        }

                        Button {
                            Task { await downloadTranscript(record: record) }
                        } label: {
                            HStack {
                                Spacer()
                                if isDownloading {
                                    ProgressView().padding(.trailing, 8)
                                    Text("下載中...")
                                } else {
                                    Image(systemName: isCached ? "arrow.clockwise" : "arrow.down.doc.fill")
                                        .padding(.trailing, 4)
                                    Text(isCached ? "重新下載" : "下載數位成績單")
                                }
                                Spacer()
                            }
                        }
                        .disabled(isDownloading)
                    }
                }
            } else if !isLoadingRecords {
                Section {
                    Text("目前無可下載的數位成績單")
                        .foregroundStyle(.secondary)
                }
            }

            // MARK: Error
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }

            // MARK: Cached transcripts list
            if !cachedTranscripts.isEmpty {
                Section("已下載的成績單") {
                    ForEach(cachedTranscripts) { transcript in
                        Button {
                            openCached(transcript: transcript)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(transcript.displayTitle)
                                    .foregroundStyle(.primary)
                                Text("下載於 \(transcript.cachedAtLabel)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete(perform: deleteCached)
                }
            }
        }
        .navigationTitle("數位成績單")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !cachedTranscripts.isEmpty {
                EditButton()
            }
        }
        .task { await loadRecords() }
        .onAppear { refreshCache() }
        .sheet(isPresented: $showPreview) {
            if let data = previewData {
                TranscriptPDFPreviewSheet(title: previewTitle, data: data)
            }
        }
    }

    // MARK: - Actions

    private func loadRecords() async {
        refreshCache()
        isLoadingRecords = true
        errorMessage = nil
        do {
            let fetched = try await SISService.shared.getDigitalTranscriptRecords()
            records = fetched
            selectedRecord = fetched.first
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingRecords = false
    }

    private func downloadTranscript(record: DigitalTranscriptRecord) async {
        isDownloading = true
        errorMessage = nil
        do {
            let data = try await SISService.shared.downloadDigitalTranscript(
                record: record,
                includeRanking: includeRanking
            )
            try cache.save(data, hy: record.hy, ht: record.ht, includeRanking: includeRanking)
            refreshCache()

            let label = cacheLabel(record: record, includeRanking: includeRanking)
            previewData = data
            previewTitle = label
            showPreview = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isDownloading = false
    }

    private func openCached(hy: Int, ht: Int, includeRanking: Bool, label: String) {
        guard let data = cache.load(hy: hy, ht: ht, includeRanking: includeRanking) else { return }
        previewData = data
        previewTitle = label
        showPreview = true
    }

    private func openCached(transcript: CachedTranscript) {
        guard let data = try? Data(contentsOf: transcript.fileURL) else { return }
        previewData = data
        previewTitle = transcript.displayTitle
        showPreview = true
    }

    private func deleteCached(at offsets: IndexSet) {
        for index in offsets {
            let t = cachedTranscripts[index]
            try? cache.delete(hy: t.hy, ht: t.ht, includeRanking: t.includeRanking)
        }
        refreshCache()
    }

    private func refreshCache() {
        cachedTranscripts = cache.allCached()
    }

    private func cacheLabel(record: DigitalTranscriptRecord, includeRanking: Bool) -> String {
        "\(record.hyHtDesc)\(includeRanking ? "（含排名）" : "")"
    }
}

// MARK: - PDF Preview Sheet

private struct TranscriptPDFPreviewSheet: View {
    let title: String
    let data: Data

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PDFPreviewView(data: data)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("關閉") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: shareURL(for: data, title: title)) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
        }
    }

    private func shareURL(for data: Data, title: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(title).pdf")
        try? data.write(to: url)
        return url
    }
}

// MARK: - Transcript Cache

/// Manages caching downloaded digital transcript PDFs.
struct TranscriptCache {
    static let shared = TranscriptCache()

    private var cacheDirectory: URL {
        let appSupport = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let base = appSupport ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("TranscriptCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? (dir as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
        return dir
    }

    private init() {}

    private func cacheKey(hy: Int, ht: Int, includeRanking: Bool) -> String {
        "transcript_\(hy)_\(ht)_\(includeRanking ? "ranked" : "plain")"
    }

    func fileURL(hy: Int, ht: Int, includeRanking: Bool) -> URL {
        cacheDirectory.appendingPathComponent("\(cacheKey(hy: hy, ht: ht, includeRanking: includeRanking)).pdf")
    }

    func save(_ data: Data, hy: Int, ht: Int, includeRanking: Bool) throws {
        let url = fileURL(hy: hy, ht: ht, includeRanking: includeRanking)
        try data.write(to: url, options: .atomic)
        try? (url as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
    }

    func load(hy: Int, ht: Int, includeRanking: Bool) -> Data? {
        try? Data(contentsOf: fileURL(hy: hy, ht: ht, includeRanking: includeRanking))
    }

    func exists(hy: Int, ht: Int, includeRanking: Bool) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(hy: hy, ht: ht, includeRanking: includeRanking).path)
    }

    func delete(hy: Int, ht: Int, includeRanking: Bool) throws {
        let url = fileURL(hy: hy, ht: ht, includeRanking: includeRanking)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    func allCached() -> [CachedTranscript] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        return contents.compactMap { url -> CachedTranscript? in
            guard url.pathExtension == "pdf",
                  let parsed = parseFilename(url.deletingPathExtension().lastPathComponent)
            else { return nil }
            let creationDate = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate
            return CachedTranscript(
                hy: parsed.hy, ht: parsed.ht, includeRanking: parsed.includeRanking,
                fileURL: url, cachedAt: creationDate ?? Date()
            )
        }
        .sorted { $0.cachedAt > $1.cachedAt }
    }

    private func parseFilename(_ name: String) -> (hy: Int, ht: Int, includeRanking: Bool)? {
        // Format: transcript_{hy}_{ht}_{ranked|plain}
        let parts = name.components(separatedBy: "_")
        guard parts.count == 4, parts[0] == "transcript",
              let hy = Int(parts[1]), let ht = Int(parts[2])
        else { return nil }
        return (hy, ht, parts[3] == "ranked")
    }
}

// MARK: - CachedTranscript Model

struct CachedTranscript: Identifiable {
    let hy: Int
    let ht: Int
    let includeRanking: Bool
    let fileURL: URL
    let cachedAt: Date

    var id: String { "\(hy)_\(ht)_\(includeRanking)" }

    var semesterLabel: String { "\(hy)學年第\(ht)學期" }
    var rankingLabel: String { includeRanking ? "（含排名）" : "" }
    var displayTitle: String { "\(semesterLabel)\(rankingLabel)" }

    var cachedAtLabel: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy/MM/dd HH:mm"
        return f.string(from: cachedAt)
    }
}
