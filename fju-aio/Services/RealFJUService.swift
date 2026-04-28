import Foundation
import os.log

final class RealFJUService: FJUServiceProtocol, @unchecked Sendable {
    private let sisService = SISService.shared
    private let sisAuthService = SISAuthService.shared
    private let estuCourseService = EstuCourseService.shared
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.fju.aio", category: "RealFJUService")
    
    // MARK: - Course Schedule
    
    func fetchCourses(semester: String) async throws -> [Course] {
        logger.info("📚 Fetching courses from ESTU for semester: \(semester)")
        
        // Use ESTU service instead of SIS
        return try await estuCourseService.fetchCourses(semester: semester)
    }
    
    // MARK: - Grades
    
    func fetchGrades(semester: String) async throws -> [Grade] {
        logger.info("📊 Fetching grades for semester: \(semester)")
        
        let parts = semester.split(separator: "-")
        guard parts.count == 2,
              let academicYear = parts.first.map(String.init),
              let semesterNum = Int(String(parts.last ?? "")) else {
            throw SISError.badRequest("Invalid semester format")
        }
        
        let scoreResponse = try await sisService.queryScores(academicYear: academicYear, semester: semesterNum)
        
        return scoreResponse.courses.map { course in
            Grade(
                id: course.courseId,
                courseName: course.courseName,
                courseCode: course.courseId,
                credits: course.credits,
                score: course.score,
                semester: semester,
                letterGrade: course.grade
            )
        }
    }
    
    func fetchGPASummary(semester: String) async throws -> GPASummary {
        logger.info("📈 Fetching GPA summary for semester: \(semester)")
        
        let parts = semester.split(separator: "-")
        guard parts.count == 2,
              let academicYear = parts.first.map(String.init),
              let semesterNum = Int(String(parts.last ?? "")) else {
            throw SISError.badRequest("Invalid semester format")
        }
        
        let scoreResponse = try await sisService.queryScores(academicYear: academicYear, semester: semesterNum)
        
        return GPASummary(
            semesterGPA: scoreResponse.semesterGPA,
            cumulativeGPA: scoreResponse.semesterGPA,
            totalCreditsEarned: scoreResponse.earnedCredits,
            totalCreditsAttempted: scoreResponse.totalCredits,
            semester: semester
        )
    }
    
    func fetchAvailableSemesters() async throws -> [String] {
        logger.info("📅 Fetching available grade semesters from SIS")
        
        return try await sisService.getAvailableGradeSemesters()
    }
    
    // MARK: - Quick Links
    
    func fetchQuickLinks() async throws -> [QuickLink] {
        logger.info("🔗 Fetching quick links")
        
        return [
            QuickLink(id: "l1", title: "校務行政系統", subtitle: "選課、成績、學籍",
                      urlString: "https://signnew.fju.edu.tw", iconSystemName: "building.columns.fill", category: .academic),
            QuickLink(id: "l2", title: "TronClass", subtitle: "線上學習平台",
                      urlString: "https://fju.tronclass.com.tw", iconSystemName: "laptopcomputer", category: .academic),
            QuickLink(id: "l3", title: "選課系統", subtitle: "加退選、課程查詢",
                      urlString: "https://signnew.fju.edu.tw", iconSystemName: "list.bullet.rectangle", category: .academic),
            QuickLink(id: "l4", title: "學生信箱", subtitle: "FJU Mail",
                      urlString: "https://mail.fju.edu.tw", iconSystemName: "envelope.fill", category: .life),
            QuickLink(id: "l5", title: "圖書館", subtitle: "館藏查詢、借閱紀錄",
                      urlString: "https://library.fju.edu.tw", iconSystemName: "books.vertical.fill", category: .library),
            QuickLink(id: "l6", title: "校園地圖", subtitle: "建築物與設施位置",
                      urlString: "https://www.fju.edu.tw/campusMap.jsp", iconSystemName: "map.fill", category: .life),
            QuickLink(id: "l7", title: "宿舍系統", subtitle: "住宿申請與管理",
                      urlString: "https://dorm.fju.edu.tw", iconSystemName: "house.fill", category: .life),
            QuickLink(id: "l8", title: "校園公告", subtitle: "最新消息與公告",
                      urlString: "https://www.fju.edu.tw", iconSystemName: "megaphone.fill", category: .other),
        ]
    }
    
    // MARK: - Attendance

    func fetchAttendanceRecords(semester: String) async throws -> [AttendanceRecord] {
        logger.info("📊 Fetching attendance records via TronClass rollcall API")

        let session = try await TronClassAuthService.shared.getValidSession()
        let userId = session.userId

        let todos = try await TronClassAPIService.shared.getTodos()
        var seen = Set<Int>()
        let courses = todos.compactMap { todo -> (id: Int, name: String)? in
            guard seen.insert(todo.course_id).inserted else { return nil }
            return (todo.course_id, todo.course_name)
        }

        guard !courses.isEmpty else { return [] }

        let rollcallService = RollcallService.shared
        var records: [AttendanceRecord] = []

        await withTaskGroup(of: [AttendanceRecord].self) { group in
            for course in courses {
                group.addTask {
                    guard let rollcalls = try? await rollcallService.fetchAttendanceRollcalls(
                        courseId: course.id, userId: userId
                    ) else { return [] }
                    return rollcalls.compactMap { r -> AttendanceRecord? in
                        guard let date = r.rollcallDate else { return nil }
                        return AttendanceRecord(
                            id: "\(r.student_rollcall_id)",
                            courseName: course.name,
                            date: date,
                            period: 0,
                            status: r.attendanceStatus,
                            rollcallTitle: r.title,
                            source: r.source
                        )
                    }
                }
            }
            for await batch in group { records.append(contentsOf: batch) }
        }

        logger.info("✅ Fetched \(records.count) attendance records total")
        return records
    }
    
    // MARK: - Calendar
    
    func fetchCalendarEvents(semester: String) async throws -> [CalendarEvent] {
        logger.info("📅 Fetching calendar events for semester: \(semester)")
        
        let icsEvents = try await fetchICSCalendarEvents()
        
        logger.info("✅ Fetched \(icsEvents.count) ICS events")
        return icsEvents
    }
    
    private func fetchICSCalendarEvents() async throws -> [CalendarEvent] {
        logger.info("📥 Fetching ICS calendar from Google Calendar")
        
        let urlString = "https://calendar.google.com/calendar/ical/6d3341c0268485919e7aef33f8326288de78791e7c4e9384a8aca25fb4197869%40group.calendar.google.com/public/basic.ics"
        guard let url = URL(string: urlString) else {
            throw SISError.badRequest("Invalid calendar URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("text/calendar", forHTTPHeaderField: "Accept")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        guard let icsContent = String(data: data, encoding: .utf8) else {
            throw SISError.invalidResponse
        }
        
        return parseICSContent(icsContent)
    }
    
    private func parseICSContent(_ content: String) -> [CalendarEvent] {
        var events: [CalendarEvent] = []
        let lines = content.components(separatedBy: .newlines)
        
        var currentEvent: [String: String] = [:]
        var isInEvent = false
        var currentKey = ""
        var currentValue = ""
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            if trimmedLine == "BEGIN:VEVENT" {
                isInEvent = true
                currentEvent = [:]
            } else if trimmedLine == "END:VEVENT" {
                if !currentKey.isEmpty {
                    currentEvent[currentKey] = currentValue
                }
                
                if let event = createCalendarEvent(from: currentEvent) {
                    events.append(event)
                }
                
                isInEvent = false
                currentKey = ""
                currentValue = ""
            } else if isInEvent {
                if trimmedLine.first == " " || trimmedLine.first == "\t" {
                    currentValue += trimmedLine.trimmingCharacters(in: .whitespaces)
                } else {
                    if !currentKey.isEmpty {
                        currentEvent[currentKey] = currentValue
                    }
                    
                    if let colonIndex = trimmedLine.firstIndex(of: ":") {
                        let key = String(trimmedLine[..<colonIndex])
                        let value = String(trimmedLine[trimmedLine.index(after: colonIndex)...])
                        currentKey = key.components(separatedBy: ";").first ?? key
                        currentValue = value
                    }
                }
            }
        }
        
        logger.info("✅ Parsed \(events.count) events from ICS calendar")
        return events
    }
    
    private func createCalendarEvent(from eventData: [String: String]) -> CalendarEvent? {
        guard let uid = eventData["UID"],
              let summary = eventData["SUMMARY"],
              let dtstart = eventData["DTSTART"] else {
            return nil
        }
        
        let dateFormatter = DateFormatter()
        
        let startDate: Date
        if dtstart.count == 8 {
            dateFormatter.dateFormat = "yyyyMMdd"
            guard let date = dateFormatter.date(from: dtstart) else { return nil }
            startDate = date
        } else {
            if dtstart.hasSuffix("Z") {
                dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
                dateFormatter.timeZone = TimeZone(identifier: "UTC")
            } else {
                dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss"
            }
            guard let date = dateFormatter.date(from: dtstart) else { return nil }
            startDate = date
        }
        
        var endDate: Date?
        if let dtend = eventData["DTEND"] {
            if dtend.count == 8 {
                dateFormatter.dateFormat = "yyyyMMdd"
                endDate = dateFormatter.date(from: dtend)
            } else {
                if dtend.hasSuffix("Z") {
                    dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
                    dateFormatter.timeZone = TimeZone(identifier: "UTC")
                } else {
                    dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss"
                }
                endDate = dateFormatter.date(from: dtend)
            }
        }
        
        let category = determineEventCategory(from: summary)
        
        return CalendarEvent(
            id: uid,
            title: summary,
            startDate: startDate,
            endDate: endDate,
            category: category,
            description: eventData["DESCRIPTION"]
        )
    }
    
    private func determineEventCategory(from summary: String) -> CalendarEvent.EventCategory {
        let lowercased = summary.lowercased()
        
        if lowercased.contains("考試") || lowercased.contains("期中考") || lowercased.contains("期末考") {
            return .exam
        } else if lowercased.contains("假") || lowercased.contains("休") {
            return .holiday
        } else if lowercased.contains("註冊") || lowercased.contains("選課") || lowercased.contains("繳費") {
            return .registration
        } else if lowercased.contains("截止") || lowercased.contains("deadline") {
            return .deadline
        } else {
            return .activity
        }
    }
    
    // MARK: - Assignments
    
    func fetchAssignments() async throws -> [Assignment] {
        logger.info("📝 Fetching assignments from TronClass todos")
        let todos = try await TronClassAPIService.shared.getTodos()
        return todos.compactMap { todo in
            guard let dueDate = todo.endDate else { return nil }
            return Assignment(
                id: "\(todo.id)",
                title: todo.title,
                courseName: todo.course_name,
                dueDate: dueDate,
                description: nil,
                source: .tronclass
            )
        }
    }
    
    func toggleAssignmentCompletion(id: String) async throws -> Assignment {
        throw SISError.notFound
    }
    
    // MARK: - Check-in
    
    func performCheckIn(courseId: String, location: String?) async throws -> CheckInResult {
        logger.info("📍 Performing check-in for course: \(courseId)")
        
        let now = Date()
        return CheckInResult(
            id: UUID().uuidString,
            courseId: courseId,
            courseName: "課程名稱",
            timestamp: now,
            location: location,
            status: .success,
            message: "簽到成功"
        )
    }
    
    // MARK: - User Profile
    
    func fetchUserProfile() async throws -> StudentProfile {
        logger.info("👤 Fetching user profile")
        return try await sisService.getStudentProfile()
    }
    
    // MARK: - Certificates
    // Note: The digital enrollment certificate (在學證明) now uses EnrollmentCertificateView
    // directly via SISService.getStuStatusCertInfo() and downloadEnrollmentCertificate().
    // These protocol stubs exist for MockFJUService compatibility.

    func fetchCertificateTypes() async throws -> [CertificateType] {
        return [
            CertificateType(id: "enrollment", name: "數位在學證明", description: nil, processingDays: 0)
        ]
    }

    func applyCertificate(type: CertificateType, purpose: String, copies: Int, language: String) async throws -> CertificateApplication {
        return CertificateApplication(
            id: UUID().uuidString,
            certificateType: type,
            purpose: purpose,
            copies: copies,
            language: language,
            status: .pending,
            appliedDate: Date(),
            estimatedCompletionDate: nil,
            downloadURL: nil
        )
    }

    func fetchCertificateApplications() async throws -> [CertificateApplication] {
        return []
    }

    func downloadCertificate(applicationId: String) async throws -> Data {
        throw SISError.notFound
    }
    
    // MARK: - Announcements
    
    func fetchAnnouncements(type: String?, page: Int, pageSize: Int) async throws -> [Announcement] {
        logger.info("📢 Fetching announcements")
        
        let response = try await sisService.getAnnouncements(
            announceType: type,
            pageNumber: page,
            pageSize: pageSize
        )
        
        let dateFormatter = ISO8601DateFormatter()
        
        return response.result.result.compactMap { announcement in
            let publishDate: Date
            if let publishDateStr = announcement.publishDate,
               let date = dateFormatter.date(from: publishDateStr) {
                publishDate = date
            } else {
                publishDate = Date()
            }
            
            return Announcement(
                id: "\(announcement.announcementSn)",
                title: announcement.title,
                content: announcement.announceData,
                publishDate: publishDate,
                category: announcement.announceCNa,
                isImportant: false
            )
        }
    }
    

}
