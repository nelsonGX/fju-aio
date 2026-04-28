import Foundation
import os.log

/// Service for all 請假 (leave request) API endpoints.
/// Base URL: https://exploreLink.fju.edu.tw/stuLeave/api
/// Auth: Bearer token from SISAuthService (same JWT used by SISService).
actor LeaveService {
    nonisolated static let shared = LeaveService()

    private let baseURL = "https://exploreLink.fju.edu.tw/stuLeave/api"
    private let authService = SISAuthService.shared
    private let networkService = NetworkService.shared
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.fju.aio", category: "LeaveService")

    private init() {}

    // MARK: - Reference Data

    /// GET /RefList/LeaveKind — top-level leave categories (一般請假, 考試請假)
    func fetchLeaveKinds() async throws -> [LeaveKind] {
        logger.info("📋 Fetching leave kinds")
        let request = try await makeRequest("GET", path: "/RefList/LeaveKind")
        let (data, response) = try await networkService.performRequest(request)
        try handleHTTPError(response)
        logRawJSON(data, label: "RefList/LeaveKind")
        let decoded = try decodeLogged(LeaveKindListResponse.self, from: data, label: "LeaveKindListResponse")
        return decoded.result
    }

    /// GET /RefList/RefLeave — leave subtypes for 一般請假
    func fetchRefLeave() async throws -> [LeaveKind] {
        logger.info("📋 Fetching ref leave subtypes")
        let request = try await makeRequest("GET", path: "/RefList/RefLeave")
        let (data, response) = try await networkService.performRequest(request)
        try handleHTTPError(response)
        logRawJSON(data, label: "RefList/RefLeave")
        let decoded = try decodeLogged(LeaveKindListResponse.self, from: data, label: "LeaveKindListResponse")
        return decoded.result
    }

    /// GET /RefList/RefExam — exam leave category options.
    func fetchExamKinds() async throws -> [LeaveKind] {
        logger.info("📋 Fetching exam kinds")
        let request = try await makeRequest("GET", path: "/RefList/RefExam")
        let (data, response) = try await networkService.performRequest(request)
        try handleHTTPError(response)
        let decoded = try JSONDecoder().decode(LeaveKindListResponse.self, from: data)
        return decoded.result
    }

    /// GET /RefList/RefLeave — concrete leave types (事假, 病假, etc.)
    func fetchRefLeaves() async throws -> [RefLeave] {
        logger.info("📋 Fetching ref leaves")
        let request = try await makeRequest("GET", path: "/RefList/RefLeave")
        let (data, response) = try await networkService.performRequest(request)
        try handleHTTPError(response)
        let decoded = try JSONDecoder().decode(RefLeaveListResponse.self, from: data)
        return decoded.result
    }

    /// GET /Course/Section — class section definitions and times.
    func fetchSections() async throws -> [LeaveSection] {
        logger.info("📋 Fetching leave sections")
        let request = try await makeRequest("GET", path: "/Course/Section")
        let (data, response) = try await networkService.performRequest(request)
        try handleHTTPError(response)
        let decoded = try JSONDecoder().decode(LeaveSectionListResponse.self, from: data)
        return decoded.result
    }

    /// GET /RefList/Hy — list of academic years
    func fetchAcademicYears() async throws -> [HyRecord] {
        logger.info("📋 Fetching academic years")
        let request = try await makeRequest("GET", path: "/RefList/Hy")
        let (data, response) = try await networkService.performRequest(request)
        try handleHTTPError(response)
        logRawJSON(data, label: "RefList/Hy")
        let decoded = try decodeLogged(HyListResponse.self, from: data, label: "HyListResponse")
        return decoded.records
    }

    /// GET /SystemTime/ApplyDeadline — deadline for leave applications this semester
    func fetchApplyDeadline() async throws -> String? {
        logger.info("📋 Fetching apply deadline")
        let request = try await makeRequest("GET", path: "/SystemTime/ApplyDeadline")
        let (data, response) = try await networkService.performRequest(request)
        try handleHTTPError(response)
        logRawJSON(data, label: "SystemTime/ApplyDeadline")
        let decoded = try decodeLogged(LeaveApplyDeadlineResponse.self, from: data, label: "LeaveApplyDeadlineResponse")
        return decoded.result
    }

    /// GET /Course/Section — period time mappings (D0–D8, DN)
    func fetchCourseSections() async throws -> [CourseSection] {
        logger.info("📋 Fetching course sections")
        let request = try await makeRequest("GET", path: "/Course/Section")
        let (data, response) = try await networkService.performRequest(request)
        try handleHTTPError(response)
        logRawJSON(data, label: "Course/Section")
        let decoded = try decodeLogged(CourseSectionListResponse.self, from: data, label: "CourseSectionListResponse")
        let sections = decoded.result.compactMap { raw -> CourseSection? in
            let no = raw.resolvedSectNo
            let na = raw.resolvedSectNa
            guard no > 0 || !na.isEmpty else { return nil }
            return CourseSection(
                sectNo: no,
                sectNa: na,
                beginTime: raw.resolvedBeginTime,
                endTime: raw.resolvedEndTime
            )
        }
        logger.debug("📋 Course/Section decoded \(sections.count) entries: \(sections.map { "\($0.sectNo)=\($0.sectNa)" }.joined(separator: ", "))")
        return sections
    }

    /// GET /RefList/FamType — family relationship types (for 喪假)
    func fetchFamTypes() async throws -> [FamTypeItem] {
        logger.info("📋 Fetching family types")
        let request = try await makeRequest("GET", path: "/RefList/FamType")
        let (data, response) = try await networkService.performRequest(request)
        try handleHTTPError(response)
        logRawJSON(data, label: "RefList/FamType")
        let decoded = try decodeLogged(FamTypeListResponse.self, from: data, label: "FamTypeListResponse")
        return decoded.result
    }

    /// GET /RefList/FamLevel — family relationship levels (for 喪假)
    func fetchFamLevels() async throws -> [FamLevelItem] {
        logger.info("📋 Fetching family levels")
        let request = try await makeRequest("GET", path: "/RefList/FamLevel")
        let (data, response) = try await networkService.performRequest(request)
        try handleHTTPError(response)
        logRawJSON(data, label: "RefList/FamLevel")
        let decoded = try decodeLogged(FamLevelListResponse.self, from: data, label: "FamLevelListResponse")
        return decoded.result
    }

    /// GET /Student/Contact — pre-fill phone/email from student profile
    func fetchStudentContact() async throws -> StudentContact? {
        logger.info("📋 Fetching student contact")
        let session = try await authService.getValidSession()
        var components = URLComponents(string: "\(baseURL)/Student/Contact")!
        components.queryItems = [URLQueryItem(name: "stuNo", value: session.empNo)]
        guard let url = components.url else { throw SISError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("zh-TW", forHTTPHeaderField: "Accept-Language")
        request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")
        let (data, httpResponse) = try await networkService.performRequest(request)
        try handleHTTPError(httpResponse)
        logRawJSON(data, label: "Student/Contact")
        let decoded = try decodeLogged(StudentContactResponse.self, from: data, label: "StudentContactResponse")
        return decoded.result
    }

    /// GET /StuLeave/{leaveApplySn} — fetch a single leave record
    func fetchLeaveRecord(leaveApplySn: Int) async throws -> LeaveRecord {
        logger.info("📋 Fetching leave record \(leaveApplySn)")
        let request = try await makeRequest("GET", path: "/StuLeave/\(leaveApplySn)")
        let (data, response) = try await networkService.performRequest(request)
        try handleHTTPError(response)
        let decoded = try JSONDecoder().decode(LeaveRecordDetailResponse.self, from: data)
        guard let record = decoded.result else { throw SISError.notFound }
        return record
    }

    /// GET /StuLeave/{leaveApplySn}/SelCou — fetch matched courses for the leave period
    func fetchSelCouCourses(leaveApplySn: Int) async throws -> [LeaveSelCouCourse] {
        logger.info("📚 Fetching SelCou for leave \(leaveApplySn)")
        let request = try await makeRequest("GET", path: "/StuLeave/\(leaveApplySn)/SelCou")
        let (data, response) = try await networkService.performRequest(request)
        try handleHTTPError(response)
        // The SelCou response may have a complex nested shape; decode as raw JSON first
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let resultArray = json["result"] as? [[String: Any]] {
            return resultArray.compactMap { parseSelCouCourse($0) }
        }
        return []
    }

    /// Final submit flow:
    ///   1. GET  /StuLeave/{sn}/LeaveAlert  — fetch any warnings (ignored, but mirrors website behaviour)
    ///   2. PUT  /StuLeave/{sn}/Confirm     — actually submit the leave application
    func confirmLeave(leaveApplySn: Int) async throws {
        logger.info("📝 Confirming leave \(leaveApplySn)")
        let session = try await authService.getValidSession()

        // Step 1: fetch alert (fire-and-forget, website always does this first)
        let alertURL = URL(string: "\(baseURL)/StuLeave/\(leaveApplySn)/LeaveAlert")!
        var alertReq = URLRequest(url: alertURL)
        alertReq.httpMethod = "GET"
        alertReq.setValue("application/json", forHTTPHeaderField: "Accept")
        alertReq.setValue("zh-TW", forHTTPHeaderField: "Accept-Language")
        alertReq.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")
        if let (data, _) = try? await networkService.performRequest(alertReq) {
            logRawJSON(data, label: "LeaveAlert")
        }

        // Step 2: PUT .../Confirm to submit
        let confirmURL = URL(string: "\(baseURL)/StuLeave/\(leaveApplySn)/Confirm")!
        var confirmReq = URLRequest(url: confirmURL)
        confirmReq.httpMethod = "PUT"
        confirmReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        confirmReq.setValue("application/json", forHTTPHeaderField: "Accept")
        confirmReq.setValue("zh-TW", forHTTPHeaderField: "Accept-Language")
        confirmReq.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")
        confirmReq.httpBody = "{}".data(using: .utf8)

        let (confirmData, confirmResponse) = try await networkService.performRequest(confirmReq)
        logRawJSON(confirmData, label: "Confirm")
        try handleHTTPError(confirmResponse)
        logger.info("✅ Leave \(leaveApplySn) submitted")
    }

    // MARK: - SelCou raw JSON parser
    // Real API shape (from /StuLeave/{sn}/SelCou):
    //   jonCouSn, avaCouSn, couCna, javaNo (course code), tchCna, avaDptCn (class name)
    //   seqTims: [{sectNo, couWek, section}]  — all scheduled periods
    //   leaveSeqTims: [{sectNo, couDate, couWek, jonCouSn, avaCouSn}]  — matched leave periods

    private func parseSelCouCourse(_ dict: [String: Any]) -> LeaveSelCouCourse? {
        guard
            let jonCouSn = dict["jonCouSn"] as? Int,
            let avaCouSn = dict["avaCouSn"] as? Int
        else { return nil }

        let couCNa   = (dict["couCna"] as? String) ?? (dict["couCNa"] as? String) ?? ""
        let couNo    = (dict["javaNo"] as? String) ?? (dict["avaNo"] as? String) ?? (dict["couNo"] as? String) ?? ""
        let tchCNa   = (dict["tchCna"] as? String) ?? (dict["tchCNa"] as? String)
        let divStr   = (dict["avaDivCn"] as? String) ?? "日"
        let dptGrdNa = (dict["avaDptCn"] as? String).map { "(\(divStr))\($0)" }

        // seqTims gives all scheduled period numbers and the day-of-week
        var sectNos: [Int] = []
        var couWek = "1"
        if let seqTims = dict["seqTims"] as? [[String: Any]] {
            for tim in seqTims {
                if let sn = tim["sectNo"] as? Int, !sectNos.contains(sn) {
                    sectNos.append(sn)
                }
                if let wek = tim["couWek"] as? String { couWek = wek }
            }
        }

        // leaveSeqTims gives exactly which date+period combos match this leave
        var leaveDates: [LeaveSelCouDate] = []
        if let tims = dict["leaveSeqTims"] as? [[String: Any]] {
            for tim in tims {
                guard
                    let dateStr = tim["couDate"] as? String,
                    let sn      = tim["sectNo"] as? Int
                else { continue }
                leaveDates.append(LeaveSelCouDate(couDate: String(dateStr.prefix(10)), sectNo: sn))
            }
        }

        logger.debug("📚 Parsed course \(couNo) \(couCNa): sectNos=\(sectNos) leaveDates=\(leaveDates.count)")

        return LeaveSelCouCourse(
            jonCouSn: jonCouSn,
            avaCouSn: avaCouSn,
            couCNa: couCNa,
            couNo: couNo,
            tchCNa: tchCNa,
            dptGrdNa: dptGrdNa,
            couWek: couWek,
            sectNos: sectNos,
            leaveDates: leaveDates
        )
    }

    // MARK: - Leave Records

    /// GET /StuLeave — list of leave records for a semester
    func fetchLeaveRecords(
        academicYear: Int,
        semester: Int,
        pageNumber: Int = 1,
        pageSize: Int = 50
    ) async throws -> [LeaveRecord] {
        logger.info("📋 Fetching leave records hy=\(academicYear) ht=\(semester)")
        let session = try await authService.getValidSession()

        var components = URLComponents(string: "\(baseURL)/StuLeave")!
        components.queryItems = [
            URLQueryItem(name: "hy", value: "\(academicYear)"),
            URLQueryItem(name: "ht", value: "\(semester)"),
            URLQueryItem(name: "stuKeyword", value: session.empNo),
            URLQueryItem(name: "pageNumber", value: "\(pageNumber)"),
            URLQueryItem(name: "pageSize", value: "\(pageSize)"),
            URLQueryItem(name: "sortBy", value: ""),
            URLQueryItem(name: "descending", value: "true"),
        ]
        guard let url = components.url else { throw SISError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("zh-TW", forHTTPHeaderField: "Accept-Language")
        request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")

        let (data, httpResponse) = try await networkService.performRequest(request)
        try handleHTTPError(httpResponse)
        let decoded = try JSONDecoder().decode(LeaveListResponse.self, from: data)
        return decoded.data
    }

    /// GET /StuLeave/OfficialLeave — official leave records
    func fetchOfficialLeaveRecords(
        academicYear: Int,
        semester: Int,
        pageNumber: Int = 1,
        pageSize: Int = 50
    ) async throws -> [LeaveRecord] {
        logger.info("📋 Fetching official leave records hy=\(academicYear) ht=\(semester)")
        let session = try await authService.getValidSession()

        var components = URLComponents(string: "\(baseURL)/StuLeave/OfficialLeave")!
        components.queryItems = [
            URLQueryItem(name: "hy", value: "\(academicYear)"),
            URLQueryItem(name: "ht", value: "\(semester)"),
            URLQueryItem(name: "stuKeyword", value: session.empNo),
            URLQueryItem(name: "pageNumber", value: "\(pageNumber)"),
            URLQueryItem(name: "pageSize", value: "\(pageSize)"),
            URLQueryItem(name: "sortBy", value: ""),
            URLQueryItem(name: "descending", value: "true"),
        ]
        guard let url = components.url else { throw SISError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("zh-TW", forHTTPHeaderField: "Accept-Language")
        request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")

        let (data, httpResponse) = try await networkService.performRequest(request)
        try handleHTTPError(httpResponse)
        let decoded = try JSONDecoder().decode(LeaveListResponse.self, from: data)
        return decoded.data
    }

    /// GET /StuLeave/Stat — leave statistics for a semester
    func fetchLeaveStat(academicYear: Int, semester: Int) async throws -> LeaveStatResult {
        logger.info("📊 Fetching leave stat hy=\(academicYear) ht=\(semester)")
        let session = try await authService.getValidSession()

        var components = URLComponents(string: "\(baseURL)/StuLeave/Stat")!
        components.queryItems = [
            URLQueryItem(name: "Hy", value: "\(academicYear)"),
            URLQueryItem(name: "Ht", value: "\(semester)"),
            URLQueryItem(name: "StuNo", value: session.empNo),
        ]
        guard let url = components.url else { throw SISError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("zh-TW", forHTTPHeaderField: "Accept-Language")
        request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")

        let (data, httpResponse) = try await networkService.performRequest(request)
        try handleHTTPError(httpResponse)
        logRawJSON(data, label: "StuLeave/Stat")
        let decoded = try decodeLogged(LeaveStatResponse.self, from: data, label: "LeaveStatResponse")
        return decoded.result
    }

    /// GET /StuLeave/{leaveApplySn} — full leave detail for editing or viewing.
    func fetchLeaveDetail(leaveApplySn: Int) async throws -> LeaveDetail {
        logger.info("📋 Fetching leave detail \(leaveApplySn)")
        let request = try await makeRequest("GET", path: "/StuLeave/\(leaveApplySn)")
        let (data, response) = try await networkService.performRequest(request)
        try handleHTTPError(response)
        let decoded = try JSONDecoder().decode(LeaveDetailResponse.self, from: data)
        return decoded.result
    }

    /// GET /LeaveApplyDoc/{leaveApplyDocSn} — download an uploaded proof file.
    func downloadLeaveApplyDoc(leaveApplyDocSn: Int) async throws -> (data: Data, filename: String) {
        logger.info("📎 Downloading leave proof file \(leaveApplyDocSn)")
        let request = try await makeRequest("GET", path: "/LeaveApplyDoc/\(leaveApplyDocSn)")
        let (data, response) = try await networkService.performRequest(request)
        try handleHTTPError(response)
        return (data, filename(from: response) ?? "leave-proof-\(leaveApplyDocSn)")
    }

    // MARK: - Submit Leave (Step 1)

    /// POST /StuLeave — create or update a leave application.
    /// Returns the new leaveApplySn.
    func submitLeave(
        leaveApplySn: Int = 0,
        academicYear: Int,
        semester: Int,
        leaveKind: Int,       // 1=一般請假, 20=考試請假
        examKind: Int,        // 0=非考試
        refLeaveSn: Int,
        officialLeaveSn: Int = 0,
        beginDate: String,
        endDate: String,
        beginSectNo: Int,
        endSectNo: Int,
        reason: String,
        phoneNumber: String = "",
        emailAccount: String = "",
        proofFileData: Data? = nil,
        proofFileName: String = "proof.pdf",
        proofFileExt: String = "pdf",
        proofFileMimeType: String = "application/octet-stream",
        proofRefDocSn: Int = 0
    ) async throws -> Int {
        logger.info("📝 Submitting leave application")
        let session = try await authService.getValidSession()

        let url = URL(string: "\(baseURL)/StuLeave")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("zh-TW", forHTTPHeaderField: "Accept-Language")
        request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        appendField("leaveApplySn", "\(leaveApplySn)")
        appendField("stuNo", session.empNo)
        appendField("hy", "\(academicYear)")
        appendField("ht", "\(semester)")
        appendField("leaveKind", "\(leaveKind)")
        appendField("examKind", "\(examKind)")
        appendField("refLeaveSn", "\(refLeaveSn)")
        appendField("officialLeaveSn", "\(officialLeaveSn)")
        appendField("beginDate", beginDate)
        appendField("endDate", endDate)
        appendField("beginSectNo", "\(beginSectNo)")
        appendField("endSectNo", "\(endSectNo)")
        appendField("leaveReason", reason)
        appendField("phoneNumber", phoneNumber)
        appendField("emailAccount", emailAccount)
        appendField("famTypeNo", "0")
        appendField("famLevelNo", "0")

        if let fileData = proofFileData {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            let filename = proofFileName.isEmpty ? "proof.\(proofFileExt)" : proofFileName
            body.append("Content-Disposition: form-data; name=\"UploadFiles[0].uploadFile\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: \(proofFileMimeType)\r\n\r\n".data(using: .utf8)!)
            body.append(fileData)
            body.append("\r\n".data(using: .utf8)!)
            appendField("UploadFiles[0].refDocSn", "\(proofRefDocSn)")
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, httpResponse) = try await networkService.performRequest(request)

        // Surface validation errors from the 400 response body
        if httpResponse.statusCode == 400 {
            if let errorResponse = try? JSONDecoder().decode(LeaveApplyAPIResponse.self, from: data),
               let errors = errorResponse.errorMessages, !errors.isEmpty {
                let msg = errors.map { $0.message }.joined(separator: "\n")
                throw SISError.badRequest(msg)
            }
            throw SISError.badRequest("請求參數錯誤")
        }
        try handleHTTPError(httpResponse)

        let decoded = try JSONDecoder().decode(LeaveApplyAPIResponse.self, from: data)
        guard decoded.success else {
            throw SISError.serverError("假單建立失敗 (statusCode=\(decoded.statusCode))")
        }
        logger.info("✅ Leave created: leaveApplySn=\(decoded.leaveApplySn)")
        return decoded.leaveApplySn
    }

    // MARK: - Submit Leave (Step 2)

    /// POST /StuLeave/{leaveApplySn}/SelCou — attach courses to a leave application.
    /// Payload is an array of per-date-per-period entries as documented.
    func selectCourses(_ entries: [SelCouPostEntry], forLeave leaveApplySn: Int) async throws {
        logger.info("📚 Selecting courses for leave \(leaveApplySn)")
        let session = try await authService.getValidSession()

        let url = URL(string: "\(baseURL)/StuLeave/\(leaveApplySn)/SelCou")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("zh-TW", forHTTPHeaderField: "Accept-Language")
        request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")

        request.httpBody = try JSONEncoder().encode(entries)

        let (data, httpResponse) = try await networkService.performRequest(request)
        try handleHTTPError(httpResponse)

        // Response may be a success bool or a simple 200 with no body check needed
        if let decoded = try? JSONDecoder().decode(LeaveSelCouResponse.self, from: data),
           !decoded.success {
            throw SISError.serverError("課程選取失敗 (statusCode=\(decoded.statusCode))")
        }
        logger.info("✅ Courses selected for leave \(leaveApplySn)")
    }

    // MARK: - Approval Flow

    /// GET /StuLeave/{leaveApplySn}/SelCou/ApplyResult — per-course approval status
    func fetchApprovalFlow(leaveApplySn: Int) async throws -> [LeaveApplyResult] {
        logger.info("📋 Fetching approval flow for leave \(leaveApplySn)")
        let request = try await makeRequest("GET", path: "/StuLeave/\(leaveApplySn)/SelCou/ApplyResult")
        let (data, response) = try await networkService.performRequest(request)
        try handleHTTPError(response)
        logRawJSON(data, label: "SelCou/ApplyResult")
        let decoded = try decodeLogged(LeaveApplyResultResponse.self, from: data, label: "LeaveApplyResultResponse")
        return decoded.result
    }

    // MARK: - Download PDF

    /// GET /StuLeave/{leaveApplySn}/LeaveForm — download leave form as PDF data
    func downloadLeaveFormPDF(leaveApplySn: Int) async throws -> Data {
        logger.info("📄 Downloading leave form PDF for \(leaveApplySn)")
        let request = try await makeRequest("GET", path: "/StuLeave/\(leaveApplySn)/LeaveForm")
        let (data, response) = try await networkService.performRequest(request)
        try handleHTTPError(response)
        logger.info("📄 Downloaded \(data.count) bytes for leave \(leaveApplySn)")
        return data
    }

    // MARK: - Revoke Leave

    /// PUT /StuLeave/{leaveApplySn}/Cancel — revoke a submitted leave with a memo
    func revokeLeave(leaveApplySn: Int, cancelMemo: String) async throws {
        logger.info("🚫 Revoking leave \(leaveApplySn)")
        let session = try await authService.getValidSession()

        let url = URL(string: "\(baseURL)/StuLeave/\(leaveApplySn)/Cancel")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("zh-TW", forHTTPHeaderField: "Accept-Language")
        request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")
        let body = ["cancelMemo": cancelMemo]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, httpResponse) = try await networkService.performRequest(request)
        logRawJSON(data, label: "Cancel")
        try handleHTTPError(httpResponse)
        logger.info("✅ Leave \(leaveApplySn) revoked")
    }

    // MARK: - Cancel Leave

    /// DELETE /StuLeave/{leaveApplySn}
    func deleteLeave(leaveApplySn: Int) async throws {
        logger.info("❌ Deleting leave \(leaveApplySn)")
        let session = try await authService.getValidSession()

        let url = URL(string: "\(baseURL)/StuLeave/\(leaveApplySn)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("zh-TW", forHTTPHeaderField: "Accept-Language")
        request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")

        let (data, httpResponse) = try await networkService.performRequest(request)
        try handleHTTPError(httpResponse)

        let decoded = try JSONDecoder().decode(LeaveBoolResponse.self, from: data)
        guard decoded.success else {
            let message = decoded.message?.info ?? "假單刪除失敗 (statusCode=\(decoded.statusCode))"
            throw SISError.serverError(message)
        }
        logger.info("✅ Leave \(leaveApplySn) deleted")
    }

    // MARK: - Helpers

    private func makeRequest(_ method: String, path: String) async throws -> URLRequest {
        let session = try await authService.getValidSession()
        let url = URL(string: "\(baseURL)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("zh-TW", forHTTPHeaderField: "Accept-Language")
        request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")
        return request
    }

    /// Log the first 2000 chars of raw JSON response for debugging.
    private func logRawJSON(_ data: Data, label: String) {
        let raw = String(data: data, encoding: .utf8) ?? "<non-UTF8>"
        let preview = raw.count > 2000 ? String(raw.prefix(2000)) + "…" : raw
        logger.debug("📦 [\(label)] raw JSON: \(preview)")
    }

    /// Decode and surface a detailed error message if decoding fails.
    private func decodeLogged<T: Decodable>(_ type: T.Type, from data: Data, label: String) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch let error as DecodingError {
            let detail: String
            switch error {
            case .keyNotFound(let key, let ctx):
                detail = "keyNotFound '\(key.stringValue)' at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))"
            case .typeMismatch(let type, let ctx):
                detail = "typeMismatch expected \(type) at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))"
            case .valueNotFound(let type, let ctx):
                detail = "valueNotFound \(type) at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))"
            case .dataCorrupted(let ctx):
                detail = "dataCorrupted: \(ctx.debugDescription)"
            @unknown default:
                detail = error.localizedDescription
            }
            logger.error("❌ [\(label)] decode failed: \(detail)")
            throw error
        }
    }

    private func handleHTTPError(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200...299: return
        case 400: throw SISError.badRequest("請求參數錯誤")
        case 401, 403: throw SISError.unauthorized
        case 404: throw SISError.notFound
        case 500...599: throw SISError.serverError("伺服器錯誤")
        default: throw SISError.invalidResponse
        }
    }

    private func filename(from response: HTTPURLResponse) -> String? {
        guard let disposition = response.value(forHTTPHeaderField: "Content-Disposition") else {
            return nil
        }

        if let encodedRange = disposition.range(of: "filename*=utf-8''") {
            let raw = String(disposition[encodedRange.upperBound...])
                .split(separator: ";", maxSplits: 1)
                .first
                .map(String.init)?
                .trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
            if let raw, let decoded = raw.removingPercentEncoding, !decoded.isEmpty {
                return decoded
            }
        }

        guard let filenameRange = disposition.range(of: "filename=") else { return nil }
        let raw = String(disposition[filenameRange.upperBound...])
            .split(separator: ";", maxSplits: 1)
            .first
            .map(String.init)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        return raw?.isEmpty == false ? raw : nil
    }
}
