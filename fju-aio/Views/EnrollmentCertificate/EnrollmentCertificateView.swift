import SwiftUI
import PDFKit

struct EnrollmentCertificateView: View {
    @State private var stuInfo: StuStatusCertInfo?
    @State private var selectedRecord: StuStatusRecord?
    @State private var selectedVersion: Int = 1  // 1 = 中文, 2 = 英文

    @State private var isLoadingInfo = false
    @State private var isDownloading = false
    @State private var errorMessage: String?

    // Cache
    @State private var cachedCerts: [CachedCertificate] = []

    // Preview sheet
    @State private var previewData: Data?
    @State private var previewTitle: String = ""
    @State private var showPreview = false

    private let cache = CertificateCache.shared

    var body: some View {
        Form {
            // MARK: Loading indicator
            if isLoadingInfo {
                Section {
                    HStack {
                        ProgressView()
                            .padding(.trailing, 8)
                        Text("讀取學籍資料中...")
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let info = stuInfo {

                // MARK: Student info
                Section("學生資訊") {
                    LabeledContent("姓名", value: info.stuCNa)
                    LabeledContent("學號", value: info.stuNo)
                    LabeledContent("系所", value: info.dptNa)
                }

                // MARK: Semester picker
                Section("選擇下載學期") {
                    let downloadable = info.hisStuStatusInfo.filter { $0.isSubmissionC || $0.isSubmissionE }
                    if downloadable.isEmpty {
                        Text("目前無可申請之學期")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("學期", selection: $selectedRecord) {
                            Text("請選擇").tag(Optional<StuStatusRecord>.none)
                            ForEach(downloadable) { record in
                                Text(record.semesterLabel)
                                    .tag(Optional(record))
                            }
                        }
                    }
                }

                // MARK: Language + download button
                if let record = selectedRecord {
                    Section("證明語言") {
                        Picker("語言", selection: $selectedVersion) {
                            if record.isSubmissionC { Text("中文版").tag(1) }
                            if record.isSubmissionE { Text("英文版").tag(2) }
                        }
                        .pickerStyle(.segmented)
                    }

                    let isCached = cache.exists(hy: record.hy, ht: record.ht, version: selectedVersion)

                    Section {
                        // If already cached, offer a quick preview button
                        if isCached {
                            Button {
                                openCached(hy: record.hy, ht: record.ht, version: selectedVersion,
                                           label: "\(record.semesterLabel) \(selectedVersion == 1 ? "中文版" : "英文版")")
                            } label: {
                                Label("預覽已快取的版本", systemImage: "doc.fill")
                            }
                        }

                        Button {
                            Task { await downloadCertificate(record: record) }
                        } label: {
                            HStack {
                                Spacer()
                                if isDownloading {
                                    ProgressView().padding(.trailing, 8)
                                    Text("下載中...")
                                } else {
                                    Image(systemName: isCached ? "arrow.clockwise" : "arrow.down.doc.fill")
                                        .padding(.trailing, 4)
                                    Text(isCached ? "重新下載" : "下載數位在學證明")
                                }
                                Spacer()
                            }
                        }
                        .disabled(isDownloading)
                    }
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

            // MARK: Cached certificates list
            if !cachedCerts.isEmpty {
                Section("已下載的證明") {
                    ForEach(cachedCerts) { cert in
                        Button {
                            openCached(cert: cert)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cert.displayTitle)
                                    .foregroundStyle(.primary)
                                Text("下載於 \(cert.cachedAtLabel)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete(perform: deleteCached)
                }
            }
        }
        .navigationTitle("在學證明")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !cachedCerts.isEmpty {
                EditButton()
            }
        }
        .task { await loadStuInfo() }
        .onAppear { refreshCache() }
        .sheet(isPresented: $showPreview) {
            if let data = previewData {
                PDFPreviewSheet(title: previewTitle, data: data)
            }
        }
    }

    // MARK: - Actions

    private func loadStuInfo() async {
        refreshCache()
        isLoadingInfo = true
        errorMessage = nil
        do {
            let info = try await SISService.shared.getStuStatusCertInfo()
            stuInfo = info
            selectedRecord = info.hisStuStatusInfo.first(where: { $0.isCurrent && ($0.isSubmissionC || $0.isSubmissionE) })
                ?? info.hisStuStatusInfo.first(where: { $0.isSubmissionC || $0.isSubmissionE })
            if let record = selectedRecord, !record.isSubmissionC, record.isSubmissionE {
                selectedVersion = 2
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingInfo = false
    }

    private func downloadCertificate(record: StuStatusRecord) async {
        isDownloading = true
        errorMessage = nil
        do {
            let data = try await SISService.shared.downloadEnrollmentCertificate(
                record: record,
                version: selectedVersion
            )
            // Save to cache
            try cache.save(data, hy: record.hy, ht: record.ht, version: selectedVersion)
            refreshCache()

            // Open preview immediately
            let label = "\(record.semesterLabel) \(selectedVersion == 1 ? "中文版" : "英文版")"
            previewData = data
            previewTitle = label
            showPreview = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isDownloading = false
    }

    private func openCached(hy: Int, ht: Int, version: Int, label: String) {
        guard let data = cache.load(hy: hy, ht: ht, version: version) else { return }
        previewData = data
        previewTitle = label
        showPreview = true
    }

    private func openCached(cert: CachedCertificate) {
        guard let data = try? Data(contentsOf: cert.fileURL) else { return }
        previewData = data
        previewTitle = cert.displayTitle
        showPreview = true
    }

    private func deleteCached(at offsets: IndexSet) {
        for index in offsets {
            let cert = cachedCerts[index]
            try? cache.delete(hy: cert.hy, ht: cert.ht, version: cert.version)
        }
        refreshCache()
    }

    private func refreshCache() {
        cachedCerts = cache.allCached()
    }
}

// MARK: - PDF Preview Sheet

private struct PDFPreviewSheet: View {
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

    /// Writes PDF data to a temp file so ShareLink can share it as a file.
    private func shareURL(for data: Data, title: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(title).pdf")
        try? data.write(to: url)
        return url
    }
}
