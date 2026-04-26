import Foundation
import os.log

actor SISService {
    static let shared = SISService()
    
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
        request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")
        
        let (data, httpResponse) = try await networkService.performRequest(request)
        try handleHTTPError(httpResponse)
        
        return try JSONDecoder().decode(SISUserInfo.self, from: data)
    }
    
    func getStudentProfile() async throws -> StudentProfile {
        logger.info("📋 Fetching student profile...")
        let session = try await authService.getValidSession()
        
        let url = URL(string: "\(baseURL)/Education/api/Student/GetProfile")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")
        
        let (data, httpResponse) = try await networkService.performRequest(request)
        try handleHTTPError(httpResponse)
        
        return try JSONDecoder().decode(StudentProfile.self, from: data)
    }
    
    // MARK: - Scores
    
    func queryScores(academicYear: String, semester: Int) async throws -> ScoreQueryResponse {
        logger.info("📊 Querying scores for \(academicYear)-\(semester)...")
        let session = try await authService.getValidSession()
        
        var components = URLComponents(string: "\(baseURL)/Education/api/Score/Query")!
        components.queryItems = [
            URLQueryItem(name: "academicYear", value: academicYear),
            URLQueryItem(name: "semester", value: "\(semester)")
        ]
        
        guard let url = components.url else {
            throw SISError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")
        
        let (data, httpResponse) = try await networkService.performRequest(request)
        try handleHTTPError(httpResponse)
        
        return try JSONDecoder().decode(ScoreQueryResponse.self, from: data)
    }
    
    // MARK: - Certificates
    
    func getCertificateTypes() async throws -> [CertType] {
        logger.info("📜 Fetching certificate types...")
        let session = try await authService.getValidSession()
        
        let url = URL(string: "\(baseURL)/Education/api/OnlineStuStatusCertApply/GetCertTypeDdl")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")
        
        let (data, httpResponse) = try await networkService.performRequest(request)
        try handleHTTPError(httpResponse)
        
        let response = try JSONDecoder().decode(CertTypesResponse.self, from: data)
        return response.data
    }
    
    func applyCertificate(certType: String, purpose: String, copies: Int, language: String) async throws -> CertApplyResponse {
        logger.info("📝 Applying for certificate type: \(certType)...")
        let session = try await authService.getValidSession()
        
        let url = URL(string: "\(baseURL)/Education/api/OnlineStuStatusCertApply/Apply")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")
        
        let applyRequest = CertApplyRequest(certType: certType, purpose: purpose, copies: copies, language: language)
        request.httpBody = try JSONEncoder().encode(applyRequest)
        
        let (data, httpResponse) = try await networkService.performRequest(request)
        try handleHTTPError(httpResponse)
        
        return try JSONDecoder().decode(CertApplyResponse.self, from: data)
    }
    
    func queryCertificateApplications(startDate: String? = nil, endDate: String? = nil, status: String? = nil) async throws -> [CertApplyRecord] {
        logger.info("📋 Querying certificate applications...")
        let session = try await authService.getValidSession()
        
        var components = URLComponents(string: "\(baseURL)/Education/api/OnlineStuStatusCertApply/QueryApplyList")!
        var queryItems: [URLQueryItem] = []
        
        if let startDate = startDate {
            queryItems.append(URLQueryItem(name: "startDate", value: startDate))
        }
        if let endDate = endDate {
            queryItems.append(URLQueryItem(name: "endDate", value: endDate))
        }
        if let status = status {
            queryItems.append(URLQueryItem(name: "status", value: status))
        }
        
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        
        guard let url = components.url else {
            throw SISError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")
        
        let (data, httpResponse) = try await networkService.performRequest(request)
        try handleHTTPError(httpResponse)
        
        let response = try JSONDecoder().decode(CertApplyListResponse.self, from: data)
        return response.data
    }
    
    func downloadCertificate(applyId: String) async throws -> Data {
        logger.info("⬇️ Downloading certificate: \(applyId)...")
        let session = try await authService.getValidSession()
        
        let url = URL(string: "\(baseURL)/Education/api/OnlineStuStatusCertApply/Download/\(applyId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/pdf", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")
        
        let (data, httpResponse) = try await networkService.performRequest(request)
        try handleHTTPError(httpResponse)
        
        return data
    }
    
    func verifyCertificate(certId: String, verifyCode: String) async throws -> CertVerifyResponse {
        logger.info("✅ Verifying certificate: \(certId)...")
        
        let url = URL(string: "\(baseURL)/Education/api/OnlineStuStatusCertApply/Verify")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let verifyRequest = CertVerifyRequest(certId: certId, verifyCode: verifyCode)
        request.httpBody = try JSONEncoder().encode(verifyRequest)
        
        let (data, httpResponse) = try await networkService.performRequest(request)
        try handleHTTPError(httpResponse)
        
        return try JSONDecoder().decode(CertVerifyResponse.self, from: data)
    }
    
    // MARK: - Leave
    
    func getLeaveTypes() async throws -> [LeaveType] {
        logger.info("📋 Fetching leave types...")
        let session = try await authService.getValidSession()
        
        let url = URL(string: "\(baseURL)/Education/api/Leave/GetLeaveTypes")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")
        
        let (data, httpResponse) = try await networkService.performRequest(request)
        try handleHTTPError(httpResponse)
        
        let response = try JSONDecoder().decode(LeaveTypesResponse.self, from: data)
        return response.data
    }
    
    func applyLeave(leaveType: String, startDate: String, endDate: String, startTime: String, endTime: String, reason: String, proofFile: Data? = nil) async throws -> LeaveApplyResponse {
        logger.info("📝 Applying for leave...")
        let session = try await authService.getValidSession()
        
        let url = URL(string: "\(baseURL)/Education/api/Leave/Apply")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")
        
        var body = Data()
        
        func appendFormField(name: String, value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        
        appendFormField(name: "leaveType", value: leaveType)
        appendFormField(name: "startDate", value: startDate)
        appendFormField(name: "endDate", value: endDate)
        appendFormField(name: "startTime", value: startTime)
        appendFormField(name: "endTime", value: endTime)
        appendFormField(name: "reason", value: reason)
        
        if let proofFile = proofFile {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"proofFile\"; filename=\"proof.pdf\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: application/pdf\r\n\r\n".data(using: .utf8)!)
            body.append(proofFile)
            body.append("\r\n".data(using: .utf8)!)
        }
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        
        let (data, httpResponse) = try await networkService.performRequest(request)
        try handleHTTPError(httpResponse)
        
        return try JSONDecoder().decode(LeaveApplyResponse.self, from: data)
    }
    
    func queryLeaveRecords(academicYear: String? = nil, semester: Int? = nil, status: String? = nil, pageNumber: Int = 1, pageSize: Int = 20) async throws -> LeaveListResponse {
        logger.info("📋 Querying leave records...")
        let session = try await authService.getValidSession()
        
        var components = URLComponents(string: "\(baseURL)/Education/api/Leave/QueryLeaveList")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "pageNumber", value: "\(pageNumber)"),
            URLQueryItem(name: "pageSize", value: "\(pageSize)")
        ]
        
        if let academicYear = academicYear {
            queryItems.append(URLQueryItem(name: "academicYear", value: academicYear))
        }
        if let semester = semester {
            queryItems.append(URLQueryItem(name: "semester", value: "\(semester)"))
        }
        if let status = status {
            queryItems.append(URLQueryItem(name: "status", value: status))
        }
        
        components.queryItems = queryItems
        
        guard let url = components.url else {
            throw SISError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")
        
        let (data, httpResponse) = try await networkService.performRequest(request)
        try handleHTTPError(httpResponse)
        
        return try JSONDecoder().decode(LeaveListResponse.self, from: data)
    }
    
    func cancelLeave(leaveId: String) async throws -> LeaveCancelResponse {
        logger.info("❌ Cancelling leave: \(leaveId)...")
        let session = try await authService.getValidSession()
        
        let url = URL(string: "\(baseURL)/Education/api/Leave/Cancel/\(leaveId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")
        
        let (data, httpResponse) = try await networkService.performRequest(request)
        try handleHTTPError(httpResponse)
        
        return try JSONDecoder().decode(LeaveCancelResponse.self, from: data)
    }
    
    // MARK: - Schedule
    
    func getCourseSchedule(academicYear: String, semester: Int) async throws -> CourseScheduleResponse {
        logger.info("📅 Fetching course schedule for \(academicYear)-\(semester)...")
        let session = try await authService.getValidSession()
        
        var components = URLComponents(string: "\(baseURL)/Education/api/Course/GetSchedule")!
        components.queryItems = [
            URLQueryItem(name: "academicYear", value: academicYear),
            URLQueryItem(name: "semester", value: "\(semester)")
        ]
        
        guard let url = components.url else {
            throw SISError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")
        
        let (data, httpResponse) = try await networkService.performRequest(request)
        try handleHTTPError(httpResponse)
        
        return try JSONDecoder().decode(CourseScheduleResponse.self, from: data)
    }
    
    // MARK: - Announcements
    
    func getAnnouncements(announceType: String? = nil, pageNumber: Int = 1, pageSize: Int = 25, sortBy: String? = nil, descending: Bool = false) async throws -> AnnouncementResponse {
        logger.info("📢 Fetching announcements...")
        
        var components = URLComponents(string: "\(baseURL)/FjuBase/api/Announcement/InEffectPagedList")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "SystemSn", value: "31"),
            URLQueryItem(name: "PageNumber", value: "\(pageNumber)"),
            URLQueryItem(name: "PageSize", value: "\(pageSize)")
        ]
        
        if let announceType = announceType {
            queryItems.append(URLQueryItem(name: "AnnounceType", value: announceType))
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
