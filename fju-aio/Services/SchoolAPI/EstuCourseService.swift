import Foundation
import os.log

actor EstuCourseService {
    nonisolated static let shared = EstuCourseService()
    
    private let baseURL = "http://estu.fju.edu.tw"
    private let coursePath = "/CheckSelList/HisListNew.aspx"
    private let authService = EstuAuthService.shared
    private let htmlParser = HTMLParser.shared
    private let tronClassAPIService = TronClassAPIService.shared
    private let networkService = NetworkService.shared
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.nelsongx.apps.fju-aio", category: "EstuCourse")
    
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
            let rawSemesters = extractSemesterOptions(from: freshHTML)
            let semesters = try await filterSemestersWithCourses(rawSemesters, session: freshSession, startingHTML: freshHTML)
            logger.info("✅ Found \(semesters.count, privacy: .public) semesters")
            return semesters
        }
        
        let rawSemesters = extractSemesterOptions(from: html)
        let semesters = try await filterSemestersWithCourses(rawSemesters, session: session, startingHTML: html)
        
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
        
        guard let currentSemester = extractCurrentSemester(from: html) ?? semesterCode else {
            throw EstuError.invalidResponse
        }
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
        
        let (data, _) = try await networkService.performRequest(
            request,
            session: urlSession,
            retryPolicy: .none
        )
        
        guard let html = String(data: data, encoding: .utf8) else {
            throw EstuError.invalidResponse
        }
        
        return html
    }

    private func filterSemestersWithCourses(_ semesters: [String], session: EstuSession, startingHTML: String) async throws -> [String] {
        guard !semesters.isEmpty else { return [] }

        logger.info("📅 Validating ESTU semesters against course rows: \(semesters.description, privacy: .public)")

        var html = startingHTML
        var validSemesters: [String] = []
        var foundCourseSemester = false

        for semester in semesters {
            guard let semesterCode = convertToSemesterCode(semester) else { continue }

            if extractCurrentSemester(from: html) != semester {
                let viewState = try htmlParser.extractViewState(from: html)
                html = try await switchSemester(session, to: semesterCode, viewState: viewState)
            }

            let currentSemester = extractCurrentSemester(from: html) ?? semester
            let courses = (try? htmlParser.extractCourses(from: html, semester: currentSemester)) ?? []
            logger.info("📅 Semester validation semester=\(semester, privacy: .public), currentSemester=\(currentSemester, privacy: .public), courseRows=\(courses.count, privacy: .public)")

            if courses.isEmpty {
                if foundCourseSemester {
                    logger.info("📅 Stopping semester validation at first older empty semester: \(semester, privacy: .public)")
                    break
                }
                continue
            }

            foundCourseSemester = true
            validSemesters.append(semester)
        }

        if validSemesters.isEmpty {
            logger.warning("⚠️ Semester validation found no course rows; falling back to raw DDL_YM semesters")
            return semesters
        }

        logger.info("📅 Validated ESTU semesters with course rows: \(validSemesters.description, privacy: .public)")
        return validSemesters
    }
    
    // MARK: - Helper Methods
    
    private func convertToSemesterCode(_ semester: String) -> String? {
        let components = semester.components(separatedBy: "-")
        guard components.count == 2 else { return nil }
        return components.joined()
    }
    
    private func extractCurrentSemester(from html: String) -> String? {
        guard let selectHTML = extractSemesterSelectHTML(from: html) else {
            logger.warning("⚠️ DDL_YM select not found while extracting current semester")
            return nil
        }

        let selectedOptionPattern = #"<option\b(?=[^>]*\bselected\b)[^>]*\bvalue\s*=\s*["'](\d{4})["'][^>]*>"#
        guard let code = firstMatch(in: selectHTML, pattern: selectedOptionPattern) else {
            logger.warning("⚠️ No selected option found in DDL_YM. ddlCodes=\(self.optionCodes(in: selectHTML).description, privacy: .public)")
            return nil
        }

        let semester = semesterIdentifier(from: code)
        logger.info("📅 Current semester selectedCode=\(code, privacy: .public), semester=\(semester ?? "nil", privacy: .public)")
        return semester
    }
    
    private func extractSemesterOptions(from html: String) -> [String] {
        guard let selectHTML = extractSemesterSelectHTML(from: html),
              let regex = try? NSRegularExpression(pattern: #"<option\b[^>]*\bvalue\s*=\s*["'](\d{4})["'][^>]*>"#, options: [.caseInsensitive]) else {
            logger.warning("⚠️ DDL_YM select not found while extracting available semesters. allFourDigitOptionCodes=\(self.optionCodes(in: html).description, privacy: .public)")
            return []
        }
        
        var seen = Set<String>()
        let matches = regex.matches(in: selectHTML, range: NSRange(selectHTML.startIndex..., in: selectHTML))
        let rawCodes = optionCodes(in: selectHTML)
        let semesters = matches.compactMap { (match: NSTextCheckingResult) -> String? in
            guard let range = Range(match.range(at: 1), in: selectHTML),
                  let semester = self.semesterIdentifier(from: String(selectHTML[range])),
                  seen.insert(semester).inserted else {
                return nil
            }
            return semester
        }

        logger.info("📅 DDL_YM semester options rawCodes=\(rawCodes.description, privacy: .public), parsed=\(semesters.description, privacy: .public)")
        if semesters.count > 6 {
            logger.warning("⚠️ Parsed unusually many DDL_YM semesters: \(semesters.description, privacy: .public)")
        }
        return semesters
    }

    private func extractSemesterSelectHTML(from html: String) -> String? {
        let pattern = #"<select\b(?=[^>]*(?:\bname\s*=\s*["']DDL_YM["']|\bid\s*=\s*["']DDL_YM["']))[^>]*>.*?</select>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range, in: html) else {
            return nil
        }

        return String(html[range])
    }

    private func semesterIdentifier(from code: String) -> String? {
        guard code.count == 4,
              let semester = code.last,
              semester == "1" || semester == "2" else {
            return nil
        }

        let year = String(code.prefix(3))
        return "\(year)-\(semester)"
    }

    private func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }

        return String(text[range])
    }

    private func optionCodes(in html: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"<option\b[^>]*\bvalue\s*=\s*["'](\d{4})["'][^>]*>"#, options: [.caseInsensitive]) else {
            return []
        }

        return regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap { match in
            guard let range = Range(match.range(at: 1), in: html) else { return nil }
            return String(html[range])
        }
    }
    
    private func isAuthenticatedPage(_ html: String) -> Bool {
        htmlParser.containsAuthenticatedEstuContent(in: html)
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
