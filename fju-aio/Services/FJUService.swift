import Foundation
import os.log

/// Unified FJU service that routes between mock and real implementations
final class FJUService: FJUServiceProtocol, @unchecked Sendable {
    
    // MARK: - Configuration
    
    enum ServiceMode {
        case mock
        case real
    }
    
    static let shared = FJUService()
    
    private var mode: ServiceMode
    private let mockService: MockFJUService
    private let realService: RealFJUService
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.fju.aio", category: "FJUService")
    
    // MARK: - Initialization
    
    private init() {
        // Start with real mode by default
        self.mode = .real
        self.mockService = MockFJUService()
        self.realService = RealFJUService()
        
        // Check if demo credentials are stored
        if let credentials = try? CredentialStore.shared.retrieveLDAPCredentials(),
           credentials.username == "demo" && credentials.password == "demo" {
            self.mode = .mock
            logger.info("🔧 FJUService initialized in MOCK mode (demo credentials detected)")
        } else {
            logger.info("🔧 FJUService initialized in REAL mode")
        }
    }
    
    // MARK: - Public API
    
    /// Switch service mode based on login credentials
    func updateMode(username: String, password: String) {
        if username == "demo" && password == "demo" {
            mode = .mock
            logger.info("🔄 Switched to MOCK mode")
        } else {
            mode = .real
            logger.info("🔄 Switched to REAL mode")
        }
    }
    
    /// Get current service mode
    var currentMode: ServiceMode {
        mode
    }
    
    private var currentService: FJUServiceProtocol {
        mode == .mock ? mockService : realService
    }
    
    private var isMockMode: Bool {
        mode == .mock
    }
    
    // MARK: - Course Schedule
    
    func fetchCourses(semester: String) async throws -> [Course] {
        let courses = try await currentService.fetchCourses(semester: semester)
        return isMockMode ? courses.map { appendMockTag(to: $0) } : courses
    }
    
    // MARK: - Grades
    
    func fetchGrades(semester: String) async throws -> [Grade] {
        let grades = try await currentService.fetchGrades(semester: semester)
        return isMockMode ? grades.map { appendMockTag(to: $0) } : grades
    }
    
    func fetchGPASummary(semester: String) async throws -> GPASummary {
        try await currentService.fetchGPASummary(semester: semester)
    }
    
    func fetchAvailableSemesters() async throws -> [String] {
        let semesters = try await currentService.fetchAvailableSemesters()
        return isMockMode ? semesters.map { "\($0) [mock]" } : semesters
    }
    
    // MARK: - Quick Links
    
    func fetchQuickLinks() async throws -> [QuickLink] {
        let links = try await currentService.fetchQuickLinks()
        return isMockMode ? links.map { appendMockTag(to: $0) } : links
    }
    
    // MARK: - Attendance
    
    func fetchAttendanceRecords(semester: String) async throws -> [AttendanceRecord] {
        let records = try await currentService.fetchAttendanceRecords(semester: semester)
        return isMockMode ? records.map { appendMockTag(to: $0) } : records
    }
    
    // MARK: - Calendar
    
    func fetchCalendarEvents(semester: String) async throws -> [CalendarEvent] {
        let events = try await currentService.fetchCalendarEvents(semester: semester)
        return isMockMode ? events.map { appendMockTag(to: $0) } : events
    }
    
    // MARK: - Assignments
    
    func fetchAssignments() async throws -> [Assignment] {
        let assignments = try await currentService.fetchAssignments()
        return isMockMode ? assignments.map { appendMockTag(to: $0) } : assignments
    }
    
    func toggleAssignmentCompletion(id: String) async throws -> Assignment {
        let assignment = try await currentService.toggleAssignmentCompletion(id: id)
        return isMockMode ? appendMockTag(to: assignment) : assignment
    }
    
    // MARK: - Check-in
    
    func performCheckIn(courseId: String, location: String?) async throws -> CheckInResult {
        let result = try await currentService.performCheckIn(courseId: courseId, location: location)
        return isMockMode ? appendMockTag(to: result) : result
    }
    
    // MARK: - User Profile
    
    func fetchUserProfile() async throws -> StudentProfile {
        let profile = try await currentService.fetchUserProfile()
        return isMockMode ? appendMockTag(to: profile) : profile
    }
    
    // MARK: - Certificates
    
    func fetchCertificateTypes() async throws -> [CertificateType] {
        let types = try await currentService.fetchCertificateTypes()
        return isMockMode ? types.map { appendMockTag(to: $0) } : types
    }
    
    func applyCertificate(type: CertificateType, purpose: String, copies: Int, language: String) async throws -> CertificateApplication {
        let application = try await currentService.applyCertificate(type: type, purpose: purpose, copies: copies, language: language)
        return isMockMode ? appendMockTag(to: application) : application
    }
    
    func fetchCertificateApplications() async throws -> [CertificateApplication] {
        let applications = try await currentService.fetchCertificateApplications()
        return isMockMode ? applications.map { appendMockTag(to: $0) } : applications
    }
    
    func downloadCertificate(applicationId: String) async throws -> Data {
        try await currentService.downloadCertificate(applicationId: applicationId)
    }
    
    // MARK: - Announcements
    
    func fetchAnnouncements(type: String?, page: Int, pageSize: Int) async throws -> [Announcement] {
        let announcements = try await currentService.fetchAnnouncements(type: type, page: page, pageSize: pageSize)
        return isMockMode ? announcements.map { appendMockTag(to: $0) } : announcements
    }
    
    // MARK: - Mock Tag Helpers
    
    private func appendMockTag(to course: Course) -> Course {
        Course(
            id: course.id,
            name: "\(course.name) [mock]",
            code: course.code,
            instructor: "\(course.instructor) [mock]",
            credits: course.credits,
            semester: course.semester,
            department: course.department,
            courseType: course.courseType,
            dayOfWeek: course.dayOfWeek,
            startPeriod: course.startPeriod,
            endPeriod: course.endPeriod,
            location: "\(course.location) [mock]",
            weeks: course.weeks,
            notes: course.notes.map { "\($0) [mock]" },
            outline: course.outline,
            color: course.color
        )
    }
    
    private func appendMockTag(to grade: Grade) -> Grade {
        Grade(
            id: grade.id,
            courseName: "\(grade.courseName) [mock]",
            courseCode: grade.courseCode,
            credits: grade.credits,
            score: grade.score,
            semester: grade.semester,
            letterGrade: grade.letterGrade
        )
    }
    
    private func appendMockTag(to link: QuickLink) -> QuickLink {
        QuickLink(
            id: link.id,
            title: "\(link.title) [mock]",
            subtitle: "\(link.subtitle) [mock]",
            urlString: link.urlString,
            iconSystemName: link.iconSystemName,
            category: link.category
        )
    }
    
    private func appendMockTag(to record: AttendanceRecord) -> AttendanceRecord {
        AttendanceRecord(
            id: record.id,
            courseName: "\(record.courseName) [mock]",
            date: record.date,
            period: record.period,
            status: record.status
        )
    }
    
    private func appendMockTag(to event: CalendarEvent) -> CalendarEvent {
        CalendarEvent(
            id: event.id,
            title: "\(event.title) [mock]",
            startDate: event.startDate,
            endDate: event.endDate,
            category: event.category,
            description: event.description.map { "\($0) [mock]" }
        )
    }
    
    private func appendMockTag(to assignment: Assignment) -> Assignment {
        Assignment(
            id: assignment.id,
            title: "\(assignment.title) [mock]",
            courseName: "\(assignment.courseName) [mock]",
            dueDate: assignment.dueDate,
            description: assignment.description.map { "\($0) [mock]" },
            source: assignment.source
        )
    }
    
    private func appendMockTag(to result: CheckInResult) -> CheckInResult {
        CheckInResult(
            id: result.id,
            courseId: result.courseId,
            courseName: "\(result.courseName) [mock]",
            timestamp: result.timestamp,
            location: result.location.map { "\($0) [mock]" },
            status: result.status,
            message: "\(result.message) [mock]"
        )
    }
    
    private func appendMockTag(to profile: StudentProfile) -> StudentProfile {
        StudentProfile(
            studentId: profile.studentId,
            name: "\(profile.name) [mock]",
            englishName: "\(profile.englishName) [mock]",
            idNumber: profile.idNumber,
            birthday: profile.birthday,
            gender: profile.gender,
            email: profile.email,
            phone: profile.phone,
            address: "\(profile.address) [mock]",
            department: "\(profile.department) [mock]",
            grade: profile.grade,
            status: profile.status,
            admissionYear: profile.admissionYear
        )
    }
    
    private func appendMockTag(to type: CertificateType) -> CertificateType {
        CertificateType(
            id: type.id,
            name: "\(type.name) [mock]",
            description: type.description.map { "\($0) [mock]" },
            processingDays: type.processingDays
        )
    }
    
    private func appendMockTag(to application: CertificateApplication) -> CertificateApplication {
        CertificateApplication(
            id: application.id,
            certificateType: appendMockTag(to: application.certificateType),
            purpose: "\(application.purpose) [mock]",
            copies: application.copies,
            language: application.language,
            status: application.status,
            appliedDate: application.appliedDate,
            estimatedCompletionDate: application.estimatedCompletionDate,
            downloadURL: application.downloadURL
        )
    }
    
    private func appendMockTag(to announcement: Announcement) -> Announcement {
        Announcement(
            id: announcement.id,
            title: "\(announcement.title) [mock]",
            content: "\(announcement.content) [mock]",
            publishDate: announcement.publishDate,
            category: announcement.category,
            isImportant: announcement.isImportant
        )
    }
}
