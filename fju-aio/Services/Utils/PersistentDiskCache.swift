import Foundation

struct PersistentCacheEntry<Value: Codable>: Codable {
    let value: Value
    let cachedAt: Date
    let schemaVersion: Int
}

struct PersistentDiskCache {
    static let shared = PersistentDiskCache()

    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        directoryName: String = "PersistentDataCache",
        fileManager: FileManager = .default
    ) {
        let baseDirectory = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]

        directory = baseDirectory.appendingPathComponent(directoryName, isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func load<Value: Codable>(_ type: Value.Type, key: String, schemaVersion: Int = 1) -> PersistentCacheEntry<Value>? {
        let url = fileURL(for: key)
        guard let data = try? Data(contentsOf: url),
              let entry = try? decoder.decode(PersistentCacheEntry<Value>.self, from: data),
              entry.schemaVersion == schemaVersion else {
            return nil
        }
        return entry
    }

    func save<Value: Codable>(_ value: Value, key: String, schemaVersion: Int = 1, cachedAt: Date = Date()) {
        let entry = PersistentCacheEntry(value: value, cachedAt: cachedAt, schemaVersion: schemaVersion)
        guard let data = try? encoder.encode(entry) else { return }
        try? data.write(to: fileURL(for: key), options: [.atomic])
    }

    func remove(key: String) {
        try? FileManager.default.removeItem(at: fileURL(for: key))
    }

    func removeAll() {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }

        for url in contents {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func fileURL(for key: String) -> URL {
        directory.appendingPathComponent(sanitized(key)).appendingPathExtension("json")
    }

    private func sanitized(_ key: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return key.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }.reduce("") { $0 + String($1) }
    }
}
