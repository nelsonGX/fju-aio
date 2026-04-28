import Foundation

final class MockFJUService: FJUServiceProtocol, @unchecked Sendable {

    // MARK: - Course Schedule

    func fetchCourses(semester: String) async throws -> [Course] {
        try await Task.sleep(for: .milliseconds(300))
        return [
            Course(id: "CSIE2004", name: "資料結構", instructor: "王大明",
                   location: "理圖 SF334", dayOfWeek: 1, startPeriod: 3, endPeriod: 4, color: "#4A90D9"),
            Course(id: "CSIE2006", name: "計算機組織", instructor: "李美華",
                   location: "理圖 SF236", dayOfWeek: 2, startPeriod: 5, endPeriod: 6, color: "#E8734A"),
            Course(id: "MATH2001", name: "線性代數", instructor: "陳志明",
                   location: "理圖 LM305", dayOfWeek: 3, startPeriod: 1, endPeriod: 2, color: "#50C878"),
            Course(id: "CSIE3001", name: "作業系統", instructor: "張文傑",
                   location: "理圖 SF435", dayOfWeek: 1, startPeriod: 6, endPeriod: 7, color: "#9B59B6"),
            Course(id: "CHIN1001", name: "大學國文", instructor: "林淑芬",
                   location: "文華樓 LB302", dayOfWeek: 4, startPeriod: 3, endPeriod: 4, color: "#F39C12"),
            Course(id: "CSIE2008", name: "演算法", instructor: "黃建華",
                   location: "理圖 SF334", dayOfWeek: 2, startPeriod: 3, endPeriod: 4, color: "#1ABC9C"),
            Course(id: "CSIE3003", name: "軟體工程", instructor: "吳佳蓉",
                   location: "理圖 SF236", dayOfWeek: 3, startPeriod: 6, endPeriod: 7, color: "#E74C3C"),
            Course(id: "PE1001", name: "體育", instructor: "趙志偉",
                   location: "體育館", dayOfWeek: 5, startPeriod: 3, endPeriod: 4, color: "#95A5A6"),
            Course(id: "ENGL2001", name: "英文閱讀與寫作", instructor: "Susan Chen",
                   location: "外語大樓 FL205", dayOfWeek: 4, startPeriod: 6, endPeriod: 7, color: "#3498DB"),
            Course(id: "CSIE2010", name: "離散數學", instructor: "周國強",
                   location: "理圖 SF334", dayOfWeek: 5, startPeriod: 1, endPeriod: 2, color: "#D35400"),
        ]
    }

    // MARK: - Grades

    func fetchGrades(semester: String) async throws -> [Grade] {
        try await Task.sleep(for: .milliseconds(300))
        if semester == "113-1" {
            return [
                Grade(id: "g1", courseName: "計算機概論", courseCode: "CSIE1001", credits: 3, score: 92, semester: "113-1", letterGrade: "A"),
                Grade(id: "g2", courseName: "微積分(一)", courseCode: "MATH1001", credits: 3, score: 85, semester: "113-1", letterGrade: "A-"),
                Grade(id: "g3", courseName: "程式設計(一)", courseCode: "CSIE1003", credits: 3, score: 95, semester: "113-1", letterGrade: "A+"),
                Grade(id: "g4", courseName: "大學英文", courseCode: "ENGL1001", credits: 2, score: 78, semester: "113-1", letterGrade: "B+"),
                Grade(id: "g5", courseName: "普通物理", courseCode: "PHYS1001", credits: 3, score: 88, semester: "113-1", letterGrade: "A-"),
                Grade(id: "g6", courseName: "體育(一)", courseCode: "PE0001", credits: 0, score: 90, semester: "113-1", letterGrade: "A"),
            ]
        }
        return [
            Grade(id: "g7", courseName: "資料結構", courseCode: "CSIE2004", credits: 3, score: nil, semester: "113-2", letterGrade: nil),
            Grade(id: "g8", courseName: "計算機組織", courseCode: "CSIE2006", credits: 3, score: nil, semester: "113-2", letterGrade: nil),
            Grade(id: "g9", courseName: "線性代數", courseCode: "MATH2001", credits: 3, score: nil, semester: "113-2", letterGrade: nil),
            Grade(id: "g10", courseName: "作業系統", courseCode: "CSIE3001", credits: 3, score: nil, semester: "113-2", letterGrade: nil),
            Grade(id: "g11", courseName: "大學國文", courseCode: "CHIN1001", credits: 2, score: nil, semester: "113-2", letterGrade: nil),
        ]
    }

    func fetchGPASummary(semester: String) async throws -> GPASummary {
        try await Task.sleep(for: .milliseconds(200))
        if semester == "113-1" {
            return GPASummary(semesterGPA: 3.72, cumulativeGPA: 3.72, totalCreditsEarned: 14, totalCreditsAttempted: 14, semester: "113-1")
        }
        return GPASummary(semesterGPA: 0, cumulativeGPA: 3.72, totalCreditsEarned: 14, totalCreditsAttempted: 28, semester: "113-2")
    }

    func fetchAvailableSemesters() async throws -> [String] {
        try await Task.sleep(for: .milliseconds(100))
        return ["113-2", "113-1"]
    }

    // MARK: - Quick Links

    func fetchQuickLinks() async throws -> [QuickLink] {
        try await Task.sleep(for: .milliseconds(200))
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
        try await Task.sleep(for: .milliseconds(300))
        let calendar = Calendar.current
        let now = Date()
        return [
            AttendanceRecord(id: "a1", courseName: "資料結構", date: calendar.date(byAdding: .day, value: -1, to: now)!, period: 3, status: .present, rollcallTitle: "2026.04.27 10:10", source: "qr"),
            AttendanceRecord(id: "a2", courseName: "資料結構", date: calendar.date(byAdding: .day, value: -1, to: now)!, period: 4, status: .present, rollcallTitle: "2026.04.27 11:10", source: "qr"),
            AttendanceRecord(id: "a3", courseName: "計算機組織", date: calendar.date(byAdding: .day, value: -2, to: now)!, period: 5, status: .present, rollcallTitle: "2026.04.26 12:10", source: "radar"),
            AttendanceRecord(id: "a4", courseName: "計算機組織", date: calendar.date(byAdding: .day, value: -2, to: now)!, period: 6, status: .late, rollcallTitle: "2026.04.26 13:40", source: "radar"),
            AttendanceRecord(id: "a5", courseName: "線性代數", date: calendar.date(byAdding: .day, value: -3, to: now)!, period: 1, status: .absent, rollcallTitle: "2026.04.25 08:10", source: "number"),
            AttendanceRecord(id: "a6", courseName: "線性代數", date: calendar.date(byAdding: .day, value: -3, to: now)!, period: 2, status: .absent, rollcallTitle: "2026.04.25 09:10", source: "number"),
            AttendanceRecord(id: "a7", courseName: "作業系統", date: calendar.date(byAdding: .day, value: -5, to: now)!, period: 6, status: .present, rollcallTitle: "2026.04.23 13:40", source: "qr"),
            AttendanceRecord(id: "a8", courseName: "大學國文", date: calendar.date(byAdding: .day, value: -4, to: now)!, period: 3, status: .excused, rollcallTitle: "2026.04.24 10:10", source: "qr"),
            AttendanceRecord(id: "a9", courseName: "演算法", date: calendar.date(byAdding: .day, value: -2, to: now)!, period: 3, status: .present, rollcallTitle: "2026.04.26 10:10", source: "qr"),
            AttendanceRecord(id: "a10", courseName: "演算法", date: calendar.date(byAdding: .day, value: -2, to: now)!, period: 4, status: .present, rollcallTitle: "2026.04.26 11:10", source: "qr"),
            AttendanceRecord(id: "a11", courseName: "資料結構", date: calendar.date(byAdding: .day, value: -8, to: now)!, period: 3, status: .present, rollcallTitle: "2026.04.20 10:10", source: "qr"),
            AttendanceRecord(id: "a12", courseName: "資料結構", date: calendar.date(byAdding: .day, value: -8, to: now)!, period: 4, status: .present, rollcallTitle: "2026.04.20 11:10", source: "qr"),
        ]
    }

    // MARK: - Calendar

    func fetchCalendarEvents(semester: String) async throws -> [CalendarEvent] {
        try await Task.sleep(for: .milliseconds(300))
        let df = DateFormatter()
        df.dateFormat = "yyyy/MM/dd"

        func d(_ s: String) -> Date { df.date(from: s) ?? Date() }

        return [
            CalendarEvent(id: "e1", title: "開學日", startDate: d("2026/02/16"), endDate: nil, category: .registration, description: "113學年度第二學期開學"),
            CalendarEvent(id: "e2", title: "加退選截止", startDate: d("2026/03/02"), endDate: nil, category: .deadline, description: "加退選最後一天"),
            CalendarEvent(id: "e3", title: "春假", startDate: d("2026/04/03"), endDate: d("2026/04/06"), category: .holiday, description: "清明節連假"),
            CalendarEvent(id: "e4", title: "期中考週", startDate: d("2026/04/13"), endDate: d("2026/04/17"), category: .exam, description: "期中考試"),
            CalendarEvent(id: "e5", title: "校慶", startDate: d("2026/05/10"), endDate: nil, category: .activity, description: "輔仁大學校慶活動"),
            CalendarEvent(id: "e6", title: "端午節", startDate: d("2026/05/31"), endDate: d("2026/06/02"), category: .holiday, description: "端午節連假"),
            CalendarEvent(id: "e7", title: "停課溫書假", startDate: d("2026/06/12"), endDate: d("2026/06/14"), category: .holiday, description: "期末考前溫書假"),
            CalendarEvent(id: "e8", title: "期末考週", startDate: d("2026/06/15"), endDate: d("2026/06/19"), category: .exam, description: "期末考試"),
            CalendarEvent(id: "e9", title: "學期結束", startDate: d("2026/06/21"), endDate: nil, category: .registration, description: "113學年度第二學期結束"),
            CalendarEvent(id: "e10", title: "暑假開始", startDate: d("2026/06/22"), endDate: nil, category: .holiday, description: nil),
        ]
    }

    // MARK: - Assignments

    func fetchAssignments() async throws -> [Assignment] {
        try await Task.sleep(for: .milliseconds(300))
        let calendar = Calendar.current
        let now = Date()
        return [
            Assignment(id: "t1", title: "HW3: Binary Search Tree 實作", courseName: "資料結構",
                       dueDate: calendar.date(byAdding: .day, value: 3, to: now)!,
                       description: "實作 BST 的 insert、delete、search 操作", source: .tronclass),
            Assignment(id: "t2", title: "Lab5: MIPS Assembly", courseName: "計算機組織",
                       dueDate: calendar.date(byAdding: .day, value: 5, to: now)!,
                       description: "使用 MIPS 組合語言完成排序程式", source: .tronclass),
            Assignment(id: "t3", title: "作文：論科技與人文", courseName: "大學國文",
                       dueDate: calendar.date(byAdding: .day, value: 7, to: now)!,
                       description: "1500字以上", source: .tronclass),
            Assignment(id: "t4", title: "HW2: 矩陣運算", courseName: "線性代數",
                       dueDate: calendar.date(byAdding: .day, value: -1, to: now)!,
                       description: "課本習題 3.1-3.5", source: .tronclass),
            Assignment(id: "t5", title: "Reading Report Ch.5", courseName: "英文閱讀與寫作",
                       dueDate: calendar.date(byAdding: .day, value: 10, to: now)!,
                       description: nil, source: .tronclass),
        ]
    }

    func toggleAssignmentCompletion(id: String) async throws -> Assignment {
        throw SISError.notFound
    }
    
    // MARK: - Check-in
    
    func performCheckIn(courseId: String, location: String?) async throws -> CheckInResult {
        try await Task.sleep(for: .milliseconds(800))
        
        let courses = try await fetchCourses(semester: "113-2")
        guard let course = courses.first(where: { $0.id == courseId }) else {
            throw NSError(domain: "MockFJUService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Course not found"])
        }
        
        let now = Date()
        let calendar = Calendar.current
        let currentMinute = calendar.component(.minute, from: now)
        let isLate = currentMinute > 10
        let status: CheckInResult.CheckInStatus = isLate ? .late : .success
        let message = isLate ? "簽到成功，但已遲到" : "簽到成功"
        
        return CheckInResult(
            id: UUID().uuidString,
            courseId: courseId,
            courseName: course.name,
            timestamp: now,
            location: location,
            status: status,
            message: message
        )
    }
    
    // MARK: - User Profile
    
    func fetchUserProfile() async throws -> StudentProfile {
        try await Task.sleep(for: .milliseconds(300))
        return StudentProfile(
            studentId: "410XXXXXX",
            name: "學生姓名",
            englishName: "Student Name",
            idNumber: "A123456789",
            birthday: "2000-01-01",
            gender: "M",
            email: "student@mail.fju.edu.tw",
            phone: "0912345678",
            address: "新北市新莊區中正路510號",
            department: "資訊工程學系",
            grade: "2",
            status: "在學",
            admissionYear: "113"
        )
    }
    
    // MARK: - Certificates
    
    func fetchCertificateTypes() async throws -> [CertificateType] {
        try await Task.sleep(for: .milliseconds(200))
        return [
            CertificateType(id: "1", name: "在學證明", description: "證明目前在學狀態", processingDays: 3),
            CertificateType(id: "2", name: "成績單", description: "歷年成績單", processingDays: 5),
            CertificateType(id: "3", name: "畢業證明", description: "證明已畢業", processingDays: 3),
            CertificateType(id: "4", name: "學位證明", description: "證明已取得學位", processingDays: 3),
        ]
    }
    
    func applyCertificate(type: CertificateType, purpose: String, copies: Int, language: String) async throws -> CertificateApplication {
        try await Task.sleep(for: .milliseconds(500))
        let calendar = Calendar.current
        let estimatedDate = calendar.date(byAdding: .day, value: type.processingDays, to: Date())
        
        return CertificateApplication(
            id: "A\(Date().timeIntervalSince1970)",
            certificateType: type,
            purpose: purpose,
            copies: copies,
            language: language,
            status: .pending,
            appliedDate: Date(),
            estimatedCompletionDate: estimatedDate,
            downloadURL: nil
        )
    }
    
    func fetchCertificateApplications() async throws -> [CertificateApplication] {
        try await Task.sleep(for: .milliseconds(300))
        let types = try await fetchCertificateTypes()
        let calendar = Calendar.current
        
        return [
            CertificateApplication(
                id: "A202604260001",
                certificateType: types[0],
                purpose: "求職使用",
                copies: 1,
                language: "zh-TW",
                status: .completed,
                appliedDate: calendar.date(byAdding: .day, value: -5, to: Date())!,
                estimatedCompletionDate: calendar.date(byAdding: .day, value: -2, to: Date())!,
                downloadURL: "https://example.com/cert.pdf"
            ),
            CertificateApplication(
                id: "A202604250001",
                certificateType: types[1],
                purpose: "申請獎學金",
                copies: 2,
                language: "zh-TW",
                status: .pending,
                appliedDate: calendar.date(byAdding: .day, value: -2, to: Date())!,
                estimatedCompletionDate: calendar.date(byAdding: .day, value: 3, to: Date())!,
                downloadURL: nil
            ),
        ]
    }
    
    func downloadCertificate(applicationId: String) async throws -> Data {
        try await Task.sleep(for: .milliseconds(500))
        return Data()
    }
    
    // MARK: - Announcements
    
    func fetchAnnouncements(type: String?, page: Int, pageSize: Int) async throws -> [Announcement] {
        try await Task.sleep(for: .milliseconds(300))
        let calendar = Calendar.current
        
        return [
            Announcement(
                id: "1",
                title: "113學年度第二學期加退選公告",
                content: "加退選時間為3月1日至3月7日，請同學把握時間。",
                publishDate: calendar.date(byAdding: .day, value: -5, to: Date())!,
                category: "academic",
                isImportant: true
            ),
            Announcement(
                id: "2",
                title: "期中考試時間公告",
                content: "期中考試週為4月13日至4月17日。",
                publishDate: calendar.date(byAdding: .day, value: -3, to: Date())!,
                category: "exam",
                isImportant: true
            ),
            Announcement(
                id: "3",
                title: "校慶活動通知",
                content: "5月10日為本校校慶日，當天停課。",
                publishDate: calendar.date(byAdding: .day, value: -1, to: Date())!,
                category: "activity",
                isImportant: false
            ),
        ]
    }
}
