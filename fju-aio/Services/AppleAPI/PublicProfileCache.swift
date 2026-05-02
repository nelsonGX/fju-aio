import Foundation

struct PublicProfileCache {
    private struct CacheEntry: Codable {
        let profile: PublicProfile
        let cachedAt: Date
    }

    static let shared = PublicProfileCache()

    private let key = "publicProfileCache.byEmpNo.v1"
    private let maxAge: TimeInterval = 60 * 60 * 12

    private init() {}

    func profiles(for empNos: [String]) -> [String: PublicProfile] {
        let wanted = Set(empNos)
        let now = Date()
        return load().reduce(into: [:]) { result, item in
            guard wanted.contains(item.key),
                  now.timeIntervalSince(item.value.cachedAt) < maxAge else { return }
            result[item.key] = item.value.profile
        }
    }

    func store(_ profiles: [PublicProfile]) {
        guard !profiles.isEmpty else { return }
        var cache = load()
        let now = Date()
        for profile in profiles {
            if let existing = cache[profile.empNo],
               existing.profile.lastUpdated >= profile.lastUpdated {
                continue
            }
            cache[profile.empNo] = CacheEntry(profile: profile, cachedAt: now)
        }
        save(cache)
    }

    private func load() -> [String: CacheEntry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let cache = try? JSONDecoder().decode([String: CacheEntry].self, from: data) else {
            return [:]
        }
        return cache
    }

    private func save(_ cache: [String: CacheEntry]) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
