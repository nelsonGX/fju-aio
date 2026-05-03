import Foundation
import os.log

actor TronClassAPIService {
    nonisolated static let shared = TronClassAPIService()
    
    private let baseURL = "https://elearn2.fju.edu.tw"
    private let outlineBaseURL = "https://travellerlink.fju.edu.tw"
    private let authService = TronClassAuthService.shared
    private let networkService = NetworkService.shared
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.nelsongx.apps.fju-aio", category: "TronClassAPI")
    
    // MARK: - In-memory cache

    private struct EnrollmentCacheEntry {
        let enrollments: [Enrollment]
        let avatars: [String: String]
        let cachedAt: Date
    }

    private struct AvatarCacheEntry {
        let avatars: [String: String]
        let cachedAt: Date
    }

    private struct UserAvatarCacheEntry {
        let avatarURL: String?
        let cachedAt: Date
    }

    /// Cached course list from /api/my-courses (one entry for the whole session)
    private var myCoursesCache: [TronClassCourseSummary]? = nil

    /// Per-courseCode enrollment + avatar cache
    private var enrollmentCache: [String: EnrollmentCacheEntry] = [:]
    private var avatarCacheByCourseId: [Int: AvatarCacheEntry] = [:]
    private var currentUserAvatarCache: [Int: UserAvatarCacheEntry] = [:]
    private var currentUserAvatarFetchTasks: [Int: Task<String?, Error>] = [:]

    /// How long enrollment data is considered fresh (10 minutes)
    private let enrollmentCacheTTL: TimeInterval = 600
    private let avatarCacheTTL: TimeInterval = 60 * 60

    private init() {}

    func clearInMemoryCaches() {
        myCoursesCache = nil
        enrollmentCache.removeAll()
        avatarCacheByCourseId.removeAll()
        currentUserAvatarCache.removeAll()
        currentUserAvatarFetchTasks.removeAll()
    }
    
    // MARK: - Notifications

    func getNotifications(limit: Int = 20) async throws -> [TronClassNotification] {
        logger.info("🔔 Fetching notifications...")
        let session = try await authService.getValidSession()

        var components = URLComponents(string: "\(baseURL)/ntf/users/\(session.userId)/notifications")!
        components.queryItems = [URLQueryItem(name: "limit", value: "\(limit)")]
        guard let url = components.url else { throw TronClassAPIError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("session=\(session.sessionId); org.springframework.web.servlet.i18n.CookieLocaleResolver.LOCALE=zh_TW", forHTTPHeaderField: "Cookie")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9,zh-TW;q=0.8,zh;q=0.7", forHTTPHeaderField: "Accept-Language")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        request.setValue("https://elearn2.fju.edu.tw", forHTTPHeaderField: "Referer")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) TronClass/common", forHTTPHeaderField: "User-Agent")

        do {
            let (data, httpResponse) = try await networkService.performRequest(request)
            try handleHTTPError(httpResponse)
            let response = try JSONDecoder().decode(TronClassNotificationsResponse.self, from: data)
            let bulletins = response.notifications.compactMap { $0.asBulletin }
            logger.info("✅ Fetched \(bulletins.count) bulletin notifications")
            return bulletins
        } catch let error as TronClassAPIError {
            throw error
        } catch {
            logger.error("❌ Failed to fetch notifications: \(error.localizedDescription)")
            throw TronClassAPIError.networkError(error)
        }
    }

    // MARK: - Todos
    
    func getTodos() async throws -> [TodoItem] {
        logger.info("📋 Fetching todos...")
        let session = try await authService.getValidSession()
        
        let url = URL(string: "\(baseURL)/api/todos")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(session.sessionId, forHTTPHeaderField: "x-session-id")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("cross-site", forHTTPHeaderField: "Sec-Fetch-Site")
        request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("zh-Hant", forHTTPHeaderField: "Accept-Language")
        request.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("capacitor://localhost", forHTTPHeaderField: "Origin")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) TronClass/common", forHTTPHeaderField: "User-Agent")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        request.setValue("empty", forHTTPHeaderField: "Sec-Fetch-Dest")
        
        do {
            let (data, httpResponse) = try await networkService.performRequest(request)
            try handleHTTPError(httpResponse)
            
            let response = try JSONDecoder().decode(TodosResponse.self, from: data)
            logger.info("✅ Fetched \(response.todo_list.count) todos")
            return response.todo_list
        } catch let error as TronClassAPIError {
            throw error
        } catch {
            logger.error("❌ Failed to fetch todos: \(error.localizedDescription)")
            throw TronClassAPIError.networkError(error)
        }
    }

    // MARK: - Course Outlines

    func getCourseOutlinesByCourseCode() async throws -> [String: CourseOutlineDetails] {
        logger.info("📚 Fetching TronClass courses for outline enrichment...")
        let tronCourses = try await getMyCourses()
        var outlines: [String: CourseOutlineDetails] = [:]

        try await withThrowingTaskGroup(of: (TronClassCourseSummary, CourseOutlineDetails?).self) { group in
            for course in tronCourses {
                group.addTask { [self] in
                    let outline = try await getCourseOutlineDetails(courseId: course.id)
                    return (course, outline)
                }
            }

            for try await (course, outline) in group {
                if let outline, outline.hasContent {
                    for key in Self.outlineLookupKeys(for: course) {
                        outlines[key] = outline
                    }
                }
            }
        }

        logger.info("✅ Fetched \(outlines.count, privacy: .public) course outlines")
        return outlines
    }

    // MARK: - Enrollments

    /// Returns enrollments and avatar URLs for the TronClass course that matches the given course code.
    /// Results are cached for `enrollmentCacheTTL` seconds so reopening the sheet is instant.
    func getEnrollments(courseCode: String) async throws -> ([Enrollment], [String: String]) {
        // Return cached entry if still fresh
        if let entry = cachedEnrollmentEntry(courseCode: courseCode) {
            logger.info("📦 Returning cached enrollments for \(courseCode, privacy: .public)")
            return (entry.enrollments, entry.avatars)
        }

        let courses = try await getMyCourses()
        guard let match = courses.first(where: { Self.outlineLookupKeys(for: $0).contains(courseCode) ||
            Self.outlineLookupKeys(for: $0).contains(where: { courseCode.contains($0) || $0.contains(courseCode) }) }) else {
            return ([], [:])
        }
        async let enrollments = fetchEnrollments(courseId: match.id)
        async let avatars = fetchAvatarsCached(courseId: match.id)
        let result = try await (enrollments, avatars)

        enrollmentCache[courseCode] = EnrollmentCacheEntry(
            enrollments: result.0,
            avatars: result.1,
            cachedAt: Date()
        )
        return result
    }

    func cachedEnrollments(courseCode: String) -> ([Enrollment], [String: String])? {
        guard let entry = cachedEnrollmentEntry(courseCode: courseCode) else { return nil }
        return (entry.enrollments, entry.avatars)
    }

    private func cachedEnrollmentEntry(courseCode: String) -> EnrollmentCacheEntry? {
        guard let entry = enrollmentCache[courseCode],
              Date().timeIntervalSince(entry.cachedAt) < enrollmentCacheTTL else {
            return nil
        }
        return entry
    }

    func getCurrentUserAvatarURL() async throws -> String? {
        let session = try await authService.getValidSession()
        if let entry = currentUserAvatarCache[session.userId],
           Date().timeIntervalSince(entry.cachedAt) < avatarCacheTTL {
            logger.info("📦 Returning cached avatar for current user")
            return entry.avatarURL
        }

        if let task = currentUserAvatarFetchTasks[session.userId] {
            return try await task.value
        }

        let task = Task<String?, Error> { [session] in
            try await self.resolveCurrentUserAvatarURL(userId: session.userId)
        }
        currentUserAvatarFetchTasks[session.userId] = task
        defer { currentUserAvatarFetchTasks[session.userId] = nil }

        let avatar = try await task.value
        currentUserAvatarCache[session.userId] = UserAvatarCacheEntry(
            avatarURL: avatar,
            cachedAt: Date()
        )
        return avatar
    }

    private func resolveCurrentUserAvatarURL(userId: Int) async throws -> String? {
        for entry in avatarCacheByCourseId.values where Date().timeIntervalSince(entry.cachedAt) < avatarCacheTTL {
            if let avatar = entry.avatars["\(userId)"] {
                return avatar
            }
        }

        let courses = try await getMyCourses()

        for course in courses {
            if let entry = avatarCacheByCourseId[course.id],
               Date().timeIntervalSince(entry.cachedAt) < avatarCacheTTL {
                if let avatar = entry.avatars["\(userId)"] {
                    return avatar
                }
                continue
            }

            let avatars = try await fetchAvatarsCached(courseId: course.id)
            if let avatar = avatars["\(userId)"] {
                return avatar
            }
        }
        return nil
    }

    private func fetchEnrollments(courseId: Int) async throws -> [Enrollment] {
        let session = try await authService.getValidSession()

        let url = URL(string: "\(baseURL)/api/course/\(courseId)/enrollments")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(session.sessionId, forHTTPHeaderField: "x-session-id")
        request.setValue("session=\(session.sessionId); org.springframework.web.servlet.i18n.CookieLocaleResolver.LOCALE=zh_TW", forHTTPHeaderField: "Cookie")
        request.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("https://elearn2.fju.edu.tw", forHTTPHeaderField: "Origin")
        request.setValue("https://elearn2.fju.edu.tw/course/\(courseId)/enrollments", forHTTPHeaderField: "Referer")
        request.setValue("zh-TW,zh-Hant;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) TronClass/common", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONEncoder().encode(EnrollmentEnrollmentsRequest())

        let (data, httpResponse) = try await networkService.performRequest(request)
        try handleHTTPError(httpResponse)

        return try JSONDecoder().decode(EnrollmentsResponse.self, from: data).enrollments
    }

    private func fetchAvatarsCached(courseId: Int) async throws -> [String: String] {
        if let entry = avatarCacheByCourseId[courseId],
           Date().timeIntervalSince(entry.cachedAt) < avatarCacheTTL {
            logger.info("📦 Returning cached avatars for course \(courseId, privacy: .public)")
            return entry.avatars
        }

        let avatars = try await fetchAvatars(courseId: courseId)
        avatarCacheByCourseId[courseId] = AvatarCacheEntry(
            avatars: avatars,
            cachedAt: Date()
        )
        return avatars
    }

    private func fetchAvatars(courseId: Int) async throws -> [String: String] {
        let session = try await authService.getValidSession()

        let url = URL(string: "\(baseURL)/api/courses/\(courseId)/users-small-avatars")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(session.sessionId, forHTTPHeaderField: "x-session-id")
        request.setValue("session=\(session.sessionId); org.springframework.web.servlet.i18n.CookieLocaleResolver.LOCALE=zh_TW", forHTTPHeaderField: "Cookie")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("https://elearn2.fju.edu.tw/course/\(courseId)/enrollments", forHTTPHeaderField: "Referer")
        request.setValue("zh-TW,zh-Hant;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) TronClass/common", forHTTPHeaderField: "User-Agent")

        let (data, httpResponse) = try await networkService.performRequest(request)
        try handleHTTPError(httpResponse)

        let avatars = try JSONDecoder().decode(AvatarsResponse.self, from: data).avatars
        return avatars.mapValues { Self.avatarURL($0, thumbnail: "64x64") }
    }

    private static func avatarURL(_ rawValue: String, thumbnail: String) -> String {
        guard var components = URLComponents(string: rawValue) else { return rawValue }
        var items = components.queryItems ?? []
        if let idx = items.firstIndex(where: { $0.name == "thumbnail" }) {
            items[idx].value = thumbnail
        } else {
            items.append(URLQueryItem(name: "thumbnail", value: thumbnail))
        }
        components.queryItems = items
        return components.url?.absoluteString ?? rawValue
    }

    private func getMyCourses() async throws -> [TronClassCourseSummary] {
        if let cached = myCoursesCache {
            return cached
        }

        let session = try await authService.getValidSession()

        let url = URL(string: "\(baseURL)/api/my-courses")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(session.sessionId, forHTTPHeaderField: "x-session-id")
        request.setValue("session=\(session.sessionId); org.springframework.web.servlet.i18n.CookieLocaleResolver.LOCALE=zh_TW", forHTTPHeaderField: "Cookie")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("https://elearn2.fju.edu.tw", forHTTPHeaderField: "Origin")
        request.setValue("https://elearn2.fju.edu.tw/user/courses", forHTTPHeaderField: "Referer")
        request.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("zh-TW,zh-Hant;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) TronClass/common", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONEncoder().encode(TronClassMyCoursesRequest())

        let (data, httpResponse) = try await networkService.performRequest(request)
        try handleHTTPError(httpResponse)

        let courses = try JSONDecoder().decode(TronClassMyCoursesResponse.self, from: data).courses
        myCoursesCache = courses
        return courses
    }

    private func getCourseOutlineDetails(courseId: Int) async throws -> CourseOutlineDetails? {
        let session = try await authService.getValidSession()

        let url = URL(string: "\(baseURL)/api/courses/\(courseId)/outline")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(session.sessionId, forHTTPHeaderField: "x-session-id")
        request.setValue("session=\(session.sessionId); org.springframework.web.servlet.i18n.CookieLocaleResolver.LOCALE=zh_TW", forHTTPHeaderField: "Cookie")
        request.setValue("https://elearn2.fju.edu.tw/course/\(courseId)/outline", forHTTPHeaderField: "Referer")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("zh-TW,zh-Hant;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")

        let (data, httpResponse) = try await networkService.performRequest(request)
        try handleHTTPError(httpResponse)

        let response = try JSONDecoder().decode(TronClassCourseOutlineResponse.self, from: data)
        guard let externalURL = response.external_url,
              let jonCouSn = Self.extractJonCouSn(from: externalURL) else {
            return nil
        }

        async let info = getCourseInfoAndBook(jonCouSn: jonCouSn)
        async let courseCP = getCourseCP(jonCouSn: jonCouSn)
        return try await makeOutlineDetails(
            externalURL: externalURL,
            info: info,
            courseCP: courseCP
        )
    }

    private func getCourseInfoAndBook(jonCouSn: Int) async throws -> OutlineCourseInfoAndBook {
        var components = URLComponents(string: "\(outlineBaseURL)/Outline/api/OutlineMaintain/CourseInfoAndBook")!
        components.queryItems = [URLQueryItem(name: "jonCouSn", value: "\(jonCouSn)")]
        guard let url = components.url else { throw TronClassAPIError.invalidResponse }

        var request = makeOutlineRequest(url: url)
        request.httpMethod = "GET"

        let (data, httpResponse) = try await networkService.performRequest(request)
        try handleHTTPError(httpResponse)

        return try JSONDecoder().decode(OutlineAPIResponse<OutlineCourseInfoAndBook>.self, from: data).result
    }

    private func getCourseCP(jonCouSn: Int) async throws -> OutlineCourseCP {
        var components = URLComponents(string: "\(outlineBaseURL)/Outline/api/OutlineMaintain/CourseCP")!
        components.queryItems = [URLQueryItem(name: "jonCouSn", value: "\(jonCouSn)")]
        guard let url = components.url else { throw TronClassAPIError.invalidResponse }

        var request = makeOutlineRequest(url: url)
        request.httpMethod = "GET"

        let (data, httpResponse) = try await networkService.performRequest(request)
        try handleHTTPError(httpResponse)

        return try JSONDecoder().decode(OutlineAPIResponse<OutlineCourseCP>.self, from: data).result
    }

    private nonisolated func makeOutlineRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer null", forHTTPHeaderField: "Authorization")
        request.setValue("https://outline.fju.edu.tw", forHTTPHeaderField: "Origin")
        request.setValue("https://outline.fju.edu.tw/", forHTTPHeaderField: "Referer")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("zh-TW,zh-Hant;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        return request
    }

    private nonisolated func makeOutlineDetails(
        externalURL: String,
        info: OutlineCourseInfoAndBook,
        courseCP: OutlineCourseCP
    ) -> CourseOutlineDetails {
        CourseOutlineDetails(
            objective: cleaned(info.dptObj),
            teachingMaterials: cleaned(info.cm),
            textbook: cleaned(info.book),
            referenceBook: cleaned(info.refBook),
            policies: cleaned(info.norms),
            otherNotes: cleaned(info.other),
            contact: cleaned(info.contact),
            officeHours: cleaned(info.courseOfficeHr) ?? cleaned(info.office),
            externalURL: externalURL,
            weeklyPlans: courseCP.weeklyCP.map {
                WeeklyCoursePlan(
                    week: $0.cweek,
                    unit: cleaned($0.unit),
                    theme: cleaned($0.theme),
                    other: cleaned($0.other),
                    physicalClassHours: $0.physicalClassHr ?? 0,
                    asyncOnlineClassHours: $0.asyncOnlineClassHr ?? 0,
                    syncOnlineClassHours: $0.syncOnlineClassHr ?? 0
                )
            }
        )
    }

    private nonisolated static func extractJonCouSn(from externalURL: String) -> Int? {
        guard let url = URL(string: externalURL) else { return nil }
        let path = url.fragment.flatMap { URLComponents(string: $0)?.path } ?? url.path
        let components = path.split(separator: "/")
        guard let index = components.firstIndex(of: "outlineView"),
              components.indices.contains(components.index(after: index)) else {
            return nil
        }
        return Int(components[components.index(after: index)])
    }

    private nonisolated static func outlineLookupKeys(for course: TronClassCourseSummary) -> Set<String> {
        var keys: Set<String> = []
        let code = course.course_code.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = course.name.trimmingCharacters(in: .whitespacesAndNewlines)

        if !code.isEmpty {
            keys.insert(code)

            if code.count > 4 {
                keys.insert(String(code.dropFirst(4)))
            }

            if code.count > 8 {
                keys.insert(String(code.dropFirst(4).dropLast(4)))
            }
        }

        if !name.isEmpty {
            keys.insert(name)
        }

        return keys
    }

    private nonisolated func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "無" { return nil }
        return trimmed
    }
    
    // MARK: - Error Handling
    
    private func handleHTTPError(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200...299:
            return
        case 401:
            logger.error("❌ Unauthorized (401)")
            throw TronClassAPIError.unauthorized
        default:
            logger.error("❌ HTTP error: \(response.statusCode)")
            throw TronClassAPIError.invalidResponse
        }
    }
}
