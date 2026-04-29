import Foundation
import os.log

actor SISService {
    nonisolated static let shared = SISService()
    
    private let baseURL = "https://travellerlink.fju.edu.tw"
    private let authService = SISAuthService.shared
    private let networkService = NetworkService.shared
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.fju.aio", category: "SIS")
    
    private init() {}
    
    // MARK: - User Info
    
    func getUserInfo() async throws -> SISUserInfo {
        logger.info("📋 Fetching user info...")
        let session = try await authService.getValidSession()
        
        let url = URL(string: "\(baseURL)/FjuBase/api/Account/GetUserInfo")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("zh-TW", forHTTPHeaderField: "Accept-Language")
        request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")
        
        let (data, httpResponse) = try await networkService.performRequest(request)
        try handleHTTPError(httpResponse)
        
        return try JSONDecoder().decode(SISUserInfo.self, from: data)
    }
    
    func getStudentProfile() async throws -> StudentProfile {
        logger.info("📋 Fetching student profile...")
        let session = try await authService.getValidSession()
        
        let url = URL(string: "\(baseURL)/Score/api/GradesInquiry/StuBaseInfo?lcId=1028")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("zh-TW", forHTTPHeaderField: "Accept-Language")
        request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")
        
        let (data, httpResponse) = try await networkService.performRequest(request)
        try handleHTTPError(httpResponse)
        
        let response = try JSONDecoder().decode(StuBaseInfoResponse.self, from: data)
        
        return StudentProfile(
            studentId: response.result.stuNo,
            name: response.result.stuCna,
            englishName: response.result.stuEna,
            idNumber: "",
            birthday: "",
            gender: "",
            email: "",
            phone: "",
            address: "",
            department: response.result.dptGrdNa,
            grade: response.result.grd ?? "1",
            status: "在學",
            admissionYear: "\(response.result.entAcaYear)"
        )
    }
    
    // MARK: - Scores

    func getAvailableGradeSemesters() async throws -> [String] {
        logger.info("📅 Fetching available grade semesters...")
        let response = try await fetchGradesInquiry()

        let semesters = Set(response.result.map { "\($0.hy)-\($0.htPeriod)" })
        return semesters.sorted { lhs, rhs in
            let leftParts = lhs.split(separator: "-").compactMap { Int($0) }
            let rightParts = rhs.split(separator: "-").compactMap { Int($0) }

            guard leftParts.count == 2, rightParts.count == 2 else {
                return lhs > rhs
            }

            if leftParts[0] != rightParts[0] {
                return leftParts[0] > rightParts[0]
            }
            return leftParts[1] > rightParts[1]
        }
    }
    
    func queryScores(academicYear: String, semester: Int) async throws -> ScoreQueryResponse {
        logger.info("📊 Querying scores for \(academicYear, privacy: .public)-\(semester, privacy: .public)...")
        let response = try await fetchGradesInquiry()
        
        let filteredCourses = response.result.filter { 
            $0.hy == Int(academicYear) && $0.htPeriod == semester 
        }
        
        let courses = filteredCourses.enumerated().map { index, grade in
            ScoreCourse(
                courseId: "\(grade.courseIdentifier)-\(index)",
                courseName: grade.couCNa,
                credits: grade.credit,
                score: parseScore(grade.scoreDisplay),
                grade: grade.scoreDisplay,
                gpa: gradePoint(for: parseScore(grade.scoreDisplay)),
                instructor: ""
            )
        }
        
        let totalCredits = courses.reduce(0) { $0 + $1.credits }
        let earnedCredits = courses.reduce(0) { sum, course in
            guard let score = course.score, score >= 60 else {
                return sum
            }
            return sum + course.credits
        }
        let semesterGPA = calculateGPA(courses)
        
        return ScoreQueryResponse(
            academicYear: academicYear,
            semester: "\(semester)",
            courses: courses,
            semesterGPA: semesterGPA,
            totalCredits: totalCredits,
            earnedCredits: earnedCredits
        )
    }

    private func fetchGradesInquiry() async throws -> GradesInquiryResponse {
        let session = try await authService.getValidSession()

        var components = URLComponents(string: "\(baseURL)/Score/api/GradesInquiry/Grades")!
        components.queryItems = [
            URLQueryItem(name: "SortBy", value: ""),
            URLQueryItem(name: "Descending", value: "true"),
            URLQueryItem(name: "LcId", value: "1028")
        ]

        guard let url = components.url else {
            throw SISError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("zh-TW", forHTTPHeaderField: "Accept-Language")
        request.setValue("https://sis.fju.edu.tw/", forHTTPHeaderField: "Referer")
        request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")

        let (data, httpResponse) = try await networkService.performRequest(request)
        try handleHTTPError(httpResponse)

        return try JSONDecoder().decode(GradesInquiryResponse.self, from: data)
    }

    private func parseScore(_ scoreDisplay: String) -> Double? {
        Double(scoreDisplay.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func calculateGPA(_ courses: [ScoreCourse]) -> Double {
        let validCourses = courses.filter { ($0.score ?? 0) > 0 && $0.credits > 0 }
        guard !validCourses.isEmpty else { return 0.0 }
        
        let totalPoints = validCourses.reduce(0.0) { sum, course in
            let gradePoint = gradePoint(for: course.score)
            return sum + (gradePoint * Double(course.credits))
        }
        let totalCredits = validCourses.reduce(0) { $0 + $1.credits }
        
        return totalCredits > 0 ? totalPoints / Double(totalCredits) : 0.0
    }

    private func gradePoint(for score: Double?) -> Double {
        guard let score else { return 0.0 }
        return convertScoreToGradePoint(score)
    }
    
    private func convertScoreToGradePoint(_ score: Double) -> Double {
        switch score {
        case 90...100: return 4.0
        case 85..<90: return 3.7
        case 80..<85: return 3.3
        case 77..<80: return 3.0
        case 73..<77: return 2.7
        case 70..<73: return 2.3
        case 67..<70: return 2.0
        case 63..<67: return 1.7
        case 60..<63: return 1.3
        default: return 0.0
        }
    }
    
    // MARK: - Certificates

    /// Step 1: Fetch available semester records for the digital enrollment certificate.
    /// GET /Education/api/OnlineStuStatusCertApply/GetStuInfo?stuNo={stuNo}&lcId=1028
    func getStuStatusCertInfo() async throws -> StuStatusCertInfo {
        logger.info("📜 Fetching StuStatusCertInfo...")
        let session = try await authService.getValidSession()

        var components = URLComponents(string: "\(baseURL)/Education/api/OnlineStuStatusCertApply/GetStuInfo")!
        components.queryItems = [
            URLQueryItem(name: "stuNo", value: session.empNo),
            URLQueryItem(name: "lcId", value: "1028")
        ]

        guard let url = components.url else { throw SISError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")

        let (data, httpResponse) = try await networkService.performRequest(request)
        try handleHTTPError(httpResponse)

        let response = try JSONDecoder().decode(StuStatusCertInfoResponse.self, from: data)
        logger.info("✅ Got \(response.result.hisStuStatusInfo.count, privacy: .public) semester records")
        return response.result
    }

    /// Step 2: Download the digital enrollment certificate PDF.
    /// GET /Education/api/OnlineStuStatusCertApply/Download?stuNO=...&entAcaYear=...&entAcaTerm=...&version=...
    /// - Parameters:
    ///   - record: The semester record from GetStuInfo to download the certificate for.
    ///   - version: 1 = 中文版, 2 = 英文版
    func downloadEnrollmentCertificate(record: StuStatusRecord, version: Int) async throws -> Data {
        let label = record.semesterLabel
        logger.info("⬇️ Downloading enrollment certificate for \(label, privacy: .public) version=\(version, privacy: .public)...")
        let session = try await authService.getValidSession()

        var components = URLComponents(string: "\(baseURL)/Education/api/OnlineStuStatusCertApply/Download")!
        components.queryItems = [
            URLQueryItem(name: "stuNO", value: record.stuNo),
            URLQueryItem(name: "entAcaYear", value: "\(record.hy)"),
            URLQueryItem(name: "entAcaTerm", value: "\(record.ht)"),
            URLQueryItem(name: "version", value: "\(version)")
        ]

        guard let url = components.url else { throw SISError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")

        let (data, httpResponse) = try await networkService.performRequest(request)
        try handleHTTPError(httpResponse)

        logger.info("✅ Certificate PDF downloaded (\(data.count, privacy: .public) bytes)")
        return data
    }
    
    // MARK: - Digital Transcript

    /// Step 1: Fetch available semester records for the digital transcript.
    /// GET /Score/api/ServiceDeskDigitalDocProvider/GetAllRecordList?stuNo={stuNo}&lcId=1028
    func getDigitalTranscriptRecords() async throws -> [DigitalTranscriptRecord] {
        logger.info("📜 Fetching digital transcript record list...")
        let session = try await authService.getValidSession()

        var components = URLComponents(string: "\(baseURL)/Score/api/ServiceDeskDigitalDocProvider/GetAllRecordList")!
        components.queryItems = [
            URLQueryItem(name: "stuNo", value: session.empNo),
            URLQueryItem(name: "lcId", value: "1028")
        ]

        guard let url = components.url else { throw SISError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("https://sis.fju.edu.tw/", forHTTPHeaderField: "Referer")
        request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")

        let (data, httpResponse) = try await networkService.performRequest(request)
        try handleHTTPError(httpResponse)

        let response = try JSONDecoder().decode(DigitalTranscriptListResponse.self, from: data)
        logger.info("✅ Got \(response.result.count, privacy: .public) digital transcript records")
        return response.result
    }

    /// Step 2: Download the digital transcript PDF for a given semester.
    /// GET /Score/api/ServiceDeskDigitalDocProvider/ExportSemeTranscriptFile?hy=...&ht=...&stuNo=...&lcid=1028&isRanking=...
    func downloadDigitalTranscript(record: DigitalTranscriptRecord, includeRanking: Bool) async throws -> Data {
        logger.info("⬇️ Downloading digital transcript for \(record.hyHtDesc, privacy: .public) ranking=\(includeRanking, privacy: .public)...")
        let session = try await authService.getValidSession()

        var components = URLComponents(string: "\(baseURL)/Score/api/ServiceDeskDigitalDocProvider/ExportSemeTranscriptFile")!
        components.queryItems = [
            URLQueryItem(name: "hy", value: "\(record.hy)"),
            URLQueryItem(name: "ht", value: "\(record.ht)"),
            URLQueryItem(name: "stuNo", value: record.stuno),
            URLQueryItem(name: "lcid", value: "1028"),
            URLQueryItem(name: "isRanking", value: includeRanking ? "true" : "false")
        ]

        guard let url = components.url else { throw SISError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("https://sis.fju.edu.tw/", forHTTPHeaderField: "Referer")
        request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")

        let (data, httpResponse) = try await networkService.performRequest(request)
        try handleHTTPError(httpResponse)

        logger.info("✅ Transcript PDF downloaded (\(data.count, privacy: .public) bytes)")
        return data
    }

    // MARK: - Schedule
    
    func getCourseSchedule(academicYear: String, semester: Int) async throws -> CourseScheduleResponse {
        logger.info("📅 Fetching course schedule for \(academicYear, privacy: .public)-\(semester, privacy: .public)...")
        _ = try await authService.getValidSession()
        
        // Note: The docs don't show a course schedule endpoint
        // This might need to be obtained from a different source or endpoint
        // For now, returning empty response
        return CourseScheduleResponse(
            academicYear: academicYear,
            semester: "\(semester)",
            courses: []
        )
    }
    
    // MARK: - Announcements
    
    func getAnnouncements(announceType: String? = nil, pageNumber: Int = 1, pageSize: Int = 25, sortBy: String? = nil, descending: Bool = false) async throws -> AnnouncementResponse {
        logger.info("📢 Fetching announcements...")
        let session = try await authService.getValidSession()
        
        var components = URLComponents(string: "\(baseURL)/FjuBase/api/Announcement/InEffectPagedList")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "SystemSn", value: "31"),
            URLQueryItem(name: "PageNumber", value: "\(pageNumber)"),
            URLQueryItem(name: "PageSize", value: "\(pageSize)")
        ]
        
        if let announceType = announceType {
            queryItems.append(URLQueryItem(name: "AnnounceType", value: announceType))
        } else {
            queryItems.append(URLQueryItem(name: "AnnounceType", value: "200"))
        }
        
        if let sortBy = sortBy {
            queryItems.append(URLQueryItem(name: "sortBy", value: sortBy))
        }
        if descending {
            queryItems.append(URLQueryItem(name: "descending", value: "true"))
        }
        
        components.queryItems = queryItems
        
        guard let url = components.url else {
            throw SISError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("zh-TW", forHTTPHeaderField: "Accept-Language")
        request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")
        
        let (data, httpResponse) = try await networkService.performRequest(request)
        try handleHTTPError(httpResponse)
        
        return try JSONDecoder().decode(AnnouncementResponse.self, from: data)
    }
    
    // MARK: - Error Handling
    
    private func handleHTTPError(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200...299:
            return
        case 400:
            throw SISError.badRequest("請求參數錯誤")
        case 401:
            throw SISError.unauthorized
        case 403:
            throw SISError.unauthorized
        case 404:
            throw SISError.notFound
        case 500...599:
            throw SISError.serverError("伺服器內部錯誤")
        default:
            throw SISError.invalidResponse
        }
    }
}
