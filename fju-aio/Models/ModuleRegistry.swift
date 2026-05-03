import SwiftUI

enum ModuleRegistry {
    static let checkInFeatureEnabledKey = "checkInFeatureEnabled"

    // MARK: - All Modules

    static let allModules: [AppModule] = [
        // In-app features (academic)
        AppModule(id: "courseSchedule", name: "看課表", icon: "calendar",
                  color: .blue, category: .academic, type: .inApp(.courseSchedule)),
        AppModule(id: "classroomSchedule", name: "教室課表", icon: "door.left.hand.open",
                  color: .mint, category: .academic, type: .inApp(.classroomSchedule)),
        AppModule(id: "grades", name: "看成績", icon: "chart.bar.fill",
                  color: .green, category: .academic, type: .inApp(.grades)),
        AppModule(id: "leaveRequest", name: "請假申請", icon: "doc.text.fill",
                  color: AppTheme.accent, category: .academic, type: .inApp(.leaveRequest)),
        AppModule(id: "attendance", name: "出缺席查詢", icon: "checkmark.circle.fill",
                  color: .teal, category: .academic, type: .inApp(.attendance)),
        AppModule(id: "checkIn", name: "課程簽到", icon: "hand.raised.fill",
                  color: AppTheme.accent, category: .academic, type: .inApp(.checkIn), isHidden: true),
        AppModule(id: "enrollmentCertificate", name: "在學證明", icon: "doc.richtext.fill",
                  color: .orange, category: .academic, type: .inApp(.enrollmentCertificate)),

        // In-app features (tools)
        AppModule(id: "semesterCalendar", name: "學期行事曆", icon: "calendar.badge.clock",
                  color: .red, category: .tools, type: .inApp(.semesterCalendar)),
        AppModule(id: "assignments", name: "作業 Todo", icon: "checklist",
                  color: .cyan, category: .tools, type: .inApp(.assignments)),
        AppModule(id: "studentGuide", name: "學生指南", icon: "book.pages.fill",
                  color: .indigo, category: .tools, type: .inApp(.studentGuide)),

        // Web links (academic)
        AppModule(id: "webTronClass", name: "TronClass", icon: "laptopcomputer",
                  color: .cyan, category: .academic,
                  type: .webLink(URL(string: "tronclass://")!)),
        AppModule(id: "webCourseSelect", name: "選課系統", icon: "list.bullet.rectangle",
                  color: .orange, category: .academic,
                  type: .webLink(URL(string: "https://signcourse.fju.edu.tw")!)),
        AppModule(id: "webWishCourseSelect", name: "全人志願選課系統", icon: "list.bullet.rectangle",
                  color: .orange, category: .academic,
                  type: .webLink(URL(string: "http://wishcourse.fju.edu.tw")!)),
        AppModule(id: "webStudentPortal", name: "學生資訊入口網", icon: "person.fill",
                  color: .orange, category: .academic,
                  type: .webLink(URL(string: "https://portal.fju.edu.tw/student")!)),

        // In-app features (life)
        AppModule(id: "campusMap", name: "校園地圖", icon: "map.fill",
                  color: .green, category: .life, type: .inApp(.campusMap)),
        AppModule(id: "contactInfo", name: "常用聯絡資訊", icon: "phone.fill",
                  color: .teal, category: .life, type: .inApp(.contactInfo)),
        AppModule(id: "webDorm", name: "宿舍系統", icon: "house.fill",
                  color: .brown, category: .life,
                  type: .webLink(URL(string: "https://dorm.fju.edu.tw/dormstu/#/")!)),

        // Web links (library)
        AppModule(id: "webLibrary", name: "圖書館", icon: "books.vertical.fill",
                  color: .orange, category: .library,
                  type: .webLink(URL(string: "https://home.lib.fju.edu.tw/TC/")!)),
        AppModule(id: "webEngNet", name: "EngNet", icon: "textformat.abc",
                  color: .blue, category: .library,
                  type: .webLink(URL(string: "http://engnet.fju.edu.tw")!)),

        // Web links (other)
        AppModule(id: "webAnnouncements", name: "學校官網", icon: "globe.fill",
                  color: .red, category: .other,
                  type: .webLink(URL(string: "https://www.fju.edu.tw")!)),
        AppModule(id: "webDSA", name: "學務處", icon: "person.2.fill",
                  color: .teal, category: .other,
                  type: .webLink(URL(string: "http://www.dsa.fju.edu.tw")!)),
        AppModule(id: "webScholarships", name: "獎助學金", icon: "dollarsign.circle.fill",
                  color: .green, category: .other,
                  type: .webLink(URL(string: "http://stuservice.fju.edu.tw/fjcugrant/")!)),
    ]

    // MARK: - Grouped by Category

    static var groupedByCategory: [(ModuleCategory, [AppModule])] {
        groupedByCategory(checkInEnabled: isCheckInFeatureEnabled)
    }

    static func groupedByCategory(checkInEnabled: Bool) -> [(ModuleCategory, [AppModule])] {
        return ModuleCategory.allCases.compactMap { category in
            let modules = allModules.filter { 
                $0.category == category && (!$0.isHidden || (checkInEnabled && $0.id == "checkIn"))
            }
            return modules.isEmpty ? nil : (category, modules)
        }
    }

    // MARK: - Lookup

    static func module(for id: String) -> AppModule? {
        allModules.first { $0.id == id }
    }

    // MARK: - Default Homepage

    static let defaultHomeModuleIDs: [String] = [
        "courseSchedule", "classroomSchedule", "grades", "leaveRequest", "assignments",
    ]
    
    // MARK: - Check-in Feature Toggle
    
    static func enableCheckInFeature() {
        UserDefaults.standard.set(true, forKey: checkInFeatureEnabledKey)
    }
    
    static func disableCheckInFeature() {
        UserDefaults.standard.set(false, forKey: checkInFeatureEnabledKey)
    }
    
    static var isCheckInFeatureEnabled: Bool {
        UserDefaults.standard.bool(forKey: checkInFeatureEnabledKey)
    }
}
