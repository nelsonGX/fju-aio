import Foundation

/// Manages caching downloaded enrollment certificate PDFs to the app's Documents directory.
struct CertificateCache {
    static let shared = CertificateCache()

    private let cacheDirectory: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("CertificateCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() {}

    // MARK: - Cache Key

    func cacheKey(hy: Int, ht: Int, version: Int) -> String {
        let lang = version == 1 ? "zh" : "en"
        return "cert_\(hy)_\(ht)_\(lang)"
    }

    // MARK: - Read / Write

    func save(_ data: Data, hy: Int, ht: Int, version: Int) throws {
        let url = fileURL(hy: hy, ht: ht, version: version)
        try data.write(to: url, options: .atomic)
    }

    func load(hy: Int, ht: Int, version: Int) -> Data? {
        let url = fileURL(hy: hy, ht: ht, version: version)
        return try? Data(contentsOf: url)
    }

    func exists(hy: Int, ht: Int, version: Int) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(hy: hy, ht: ht, version: version).path)
    }

    func delete(hy: Int, ht: Int, version: Int) throws {
        let url = fileURL(hy: hy, ht: ht, version: version)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    func removeAll() {
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return }

        for url in contents {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - List All Cached Items

    /// Returns metadata for every cached certificate, sorted newest first.
    func allCached() -> [CachedCertificate] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        return contents.compactMap { url -> CachedCertificate? in
            guard url.pathExtension == "pdf",
                  let parsed = parseCacheFilename(url.deletingPathExtension().lastPathComponent)
            else { return nil }
            let creationDate = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate
            return CachedCertificate(
                hy: parsed.hy, ht: parsed.ht, version: parsed.version,
                fileURL: url, cachedAt: creationDate ?? Date()
            )
        }
        .sorted { $0.cachedAt > $1.cachedAt }
    }

    // MARK: - Private Helpers

    func fileURL(hy: Int, ht: Int, version: Int) -> URL {
        cacheDirectory.appendingPathComponent("\(cacheKey(hy: hy, ht: ht, version: version)).pdf")
    }

    private func parseCacheFilename(_ name: String) -> (hy: Int, ht: Int, version: Int)? {
        // Format: cert_{hy}_{ht}_{lang}
        let parts = name.components(separatedBy: "_")
        guard parts.count == 4, parts[0] == "cert",
              let hy = Int(parts[1]), let ht = Int(parts[2])
        else { return nil }
        let version = parts[3] == "zh" ? 1 : 2
        return (hy, ht, version)
    }
}

// MARK: - Model

struct CachedCertificate: Identifiable {
    let hy: Int
    let ht: Int
    let version: Int
    let fileURL: URL
    let cachedAt: Date

    var id: String { "\(hy)_\(ht)_\(version)" }

    var semesterLabel: String { "\(hy)學年第\(ht)學期" }
    var versionLabel: String { version == 1 ? "中文版" : "英文版" }

    var displayTitle: String { "\(semesterLabel) \(versionLabel)" }

    var cachedAtLabel: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy/MM/dd HH:mm"
        return f.string(from: cachedAt)
    }
}
