import Foundation
import os.log

actor EstuCourseService {
    nonisolated static let shared = EstuCourseService()
    
    private let baseURL = "http://estu.fju.edu.tw"
    private let coursePath = "/CheckSelList/HisListNew.aspx"
    private let authService = EstuAuthService.shared
    private let htmlParser = HTMLParser.shared
    private let tronClassAPIService = TronClassAPIService.shared
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.fju.aio", category: "EstuCourse")
    
    private init() {}
    
    // MARK: - Public API
    
    func fetchCourses(semester: String) async throws -> [Course] {
        logger.info("📚 Fetching courses for semester: \(semester, privacy: .public)")
        
        let session = try await authService.getValidSession()
        
        let semesterCode = convertToSemesterCode(semester)
        
        do {
            let estuCourses = try await fetchCoursesWithSession(session, semesterCode: semesterCode)
            let enrichedCourses = await enrichWithOutlineData(estuCourses)
            let courses = enrichedCourses.flatMap { $0.toCourses() }
            logger.info("✅ Fetched \(courses.count, privacy: .public) courses")
            return courses
        } catch let estuError as EstuError {
            // Session cookie is gone (e.g. app restart), or other ESTU error — force re-login and retry
            logger.warning("⚠️ ESTU error caught (\(estuError.localizedDescription, privacy: .public)), forcing re-login...")
            let freshSession = try await authService.forceRelogin()
            let estuCourses = try await fetchCoursesWithSession(freshSession, semesterCode: semesterCode)
            let enrichedCourses = await enrichWithOutlineData(estuCourses)
            let courses = enrichedCourses.flatMap { $0.toCourses() }
            logger.info("✅ Fetched \(courses.count, privacy: .public) courses after re-login")
            return courses
        } catch {
            logger.error("❌ fetchCourses failed with error: \(error.localizedDescription, privacy: .public) (type: \(String(describing: type(of: error)), privacy: .public))")
            throw error
        }
    }
    
    func fetchAvailableSemesters() async throws -> [String] {
        logger.info("📅 Fetching available semesters")
        
        let session = try await authService.getValidSession()
        
        guard let html = session.loginResponseHTML else {
            logger.warning("⚠️ No login response HTML, forcing re-login for semesters")
            let freshSession = try await authService.forceRelogin()
            guard let freshHTML = freshSession.loginResponseHTML else {
                throw EstuError.sessionExpired
            }
            let semesters = extractSemesterOptions(from: freshHTML)
            logger.info("✅ Found \(semesters.count, privacy: .public) semesters")
            return semesters
        }
        
        let semesters = extractSemesterOptions(from: html)
        
        logger.info("✅ Found \(semesters.count, privacy: .public) semesters")
        return semesters
    }
    
    // MARK: - Private Methods
    
    private func fetchCoursesWithSession(_ session: EstuSession, semesterCode: String?) async throws -> [EstuCourse] {
        logger.info("🔄 fetchCoursesWithSession: semesterCode=\(semesterCode ?? "nil", privacy: .public)")
        
        // Use the authenticated HTML from the login response directly.
        // A bare GET to HisListNew.aspx always returns the login form, so we must
        // rely on the HTML that was returned by the POST login.
        guard var html = session.loginResponseHTML, isAuthenticatedPage(html) else {
            logger.error("❌ No authenticated login response HTML available — session needs re-login")
            throw EstuError.sessionExpired
        }
        logger.info("📄 Using login response HTML, length=\(html.count, privacy: .public)")
        
        if let semesterCode = semesterCode {
            logger.info("🔄 Switching to semester: \(semesterCode, privacy: .public)")
            // Parse fresh viewState from the current HTML (tokens are one-time-use)
            let viewState = try htmlParser.extractViewState(from: html)
            html = try await switchSemester(session, to: semesterCode, viewState: viewState)
            logger.info("📄 Got switched semester HTML, length=\(html.count, privacy: .public)")
        }
        
        let currentSemester = extractCurrentSemester(from: html) ?? "114-2"
        logger.info("📅 Current semester: \(currentSemester, privacy: .public)")
        
        let courses = try htmlParser.extractCourses(from: html, semester: currentSemester)
        logger.info("📚 extractCourses returned \(courses.count, privacy: .public) courses")
        for course in courses {
            let slots = course.schedules.map { "\($0.dayOfWeek) \($0.periods) @\($0.classroom)" }.joined(separator: " | ")
            logger.info("  📖 \(course.name, privacy: .public) [\(slots, privacy: .public)]")
        }
        return courses
    }

    private func enrichWithOutlineData(_ courses: [EstuCourse]) async -> [EstuCourse] {
        do {
            let outlinesByCourseCode = try await tronClassAPIService.getCourseOutlinesByCourseCode()
            guard !outlinesByCourseCode.isEmpty else { return courses }

            return courses.map { course in
                let outline = outline(for: course, in: outlinesByCourseCode)
                if outline == nil {
                    logger.debug("No outline match for \(course.name, privacy: .public), code=\(course.code, privacy: .public)")
                }
                return course.withOutline(outline)
            }
        } catch {
            logger.warning("⚠️ Could not enrich courses with outline data: \(error.localizedDescription, privacy: .public)")
            return courses
        }
    }

    private func outline(for course: EstuCourse, in outlinesByKey: [String: CourseOutlineDetails]) -> CourseOutlineDetails? {
        let keys = [
            course.code,
            course.id,
            course.name
        ]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

        for key in keys {
            if let outline = outlinesByKey[key] {
                return outline
            }
        }

        return outlinesByKey.first { entry in
            keys.contains { courseKey in
                entry.key.contains(courseKey) || courseKey.contains(entry.key)
            }
        }?.value
    }
    
    private func switchSemester(_ session: EstuSession, to semesterCode: String, viewState: EstuViewState) async throws -> String {
        let url = URL(string: "\(baseURL)\(coursePath)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("zh-TW,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("\(baseURL)\(coursePath)", forHTTPHeaderField: "Referer")
        request.setValue("1", forHTTPHeaderField: "Upgrade-Insecure-Requests")
        
        let formData = [
            "__EVENTTARGET": "DDL_YM",
            "__EVENTARGUMENT": "",
            "__LASTFOCUS": "",
            "__VIEWSTATE": viewState.viewState,
            "__VIEWSTATEGENERATOR": viewState.viewStateGenerator,
            "__EVENTVALIDATION": viewState.eventValidation,
            "DDL_YM": semesterCode
        ]
        
        request.httpBody = formData.percentEncoded()
        
        // Use the auth service's URLSession which has the cookies
        let urlSession = await authService.getURLSession()
        
        let (data, _) = try await urlSession.data(for: request)
        
        guard let html = String(data: data, encoding: .utf8) else {
            throw EstuError.invalidResponse
        }
        
        return html
    }
    
    // MARK: - Helper Methods
    
    private func convertToSemesterCode(_ semester: String) -> String? {
        let components = semester.components(separatedBy: "-")
        guard components.count == 2 else { return nil }
        return components.joined()
    }
    
    private func extractCurrentSemester(from html: String) -> String? {
        let pattern = #"<select[^>]*name="DDL_YM"[^>]*>.*?<option[^>]*selected[^>]*value="(\d+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else {
            return nil
        }
        
        let code = String(html[range])
        guard code.count == 4 else { return nil }
        let year = String(code.prefix(3))
        let sem = String(code.suffix(1))
        return "\(year)-\(sem)"
    }
    
    private func extractSemesterOptions(from html: String) -> [String] {
        let pattern = #"<option[^>]*value="(\d{4})""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }
        
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        return matches.compactMap { match in
            guard let range = Range(match.range(at: 1), in: html) else { return nil }
            let code = String(html[range])
            guard code.count == 4 else { return nil }
            let year = String(code.prefix(3))
            let sem = String(code.suffix(1))
            return "\(year)-\(sem)"
        }
    }
    
    private func isAuthenticatedPage(_ html: String) -> Bool {
        if html.contains("id=\"GV_NewSellist\"") { return true }
        if html.contains("id=\"LabStuno1\"") { return true }
        return false
    }
}

private nonisolated extension Dictionary where Key == String, Value == String {
    func percentEncoded() -> Data? {
        // Use a restricted character set for application/x-www-form-urlencoded
        // This must NOT include +, =, &, / which are significant in form encoding
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        
        return map { key, value in
            let escapedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
            let escapedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
            return "\(escapedKey)=\(escapedValue)"
        }
        .joined(separator: "&")
        .data(using: .utf8)
    }
}
