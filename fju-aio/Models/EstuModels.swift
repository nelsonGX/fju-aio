import Foundation

/// A single time slot for a course (day + period range + classroom)
nonisolated struct EstuScheduleSlot: Hashable, Sendable {
    let dayOfWeek: String   // "一", "二", etc.
    let weeks: String       // "全", "單", "雙"
    let periods: String     // Raw period string e.g. "D3-D4"
    let classroom: String
    
    var startPeriod: Int {
        let (start, _) = EstuScheduleSlot.parsePeriods(periods)
        return start
    }
    
    var endPeriod: Int {
        let (_, end) = EstuScheduleSlot.parsePeriods(periods)
        return end
    }
    
    var dayOfWeekNumber: Int {
        switch dayOfWeek {
        case "一": return 1
        case "二": return 2
        case "三": return 3
        case "四": return 4
        case "五": return 5
        case "六": return 6
        case "日": return 7
        default: return 0
        }
    }
    
    /// Parse period strings like "D3-D4", "DN-DE", "D5-D6"
    static func parsePeriods(_ periods: String) -> (start: Int, end: Int) {
        let components = periods.components(separatedBy: "-")
        let startStr = components.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let endStr = components.count > 1 ? components[1].trimmingCharacters(in: .whitespacesAndNewlines) : startStr
        
        let start = periodToNumber(startStr)
        let end = periodToNumber(endStr)
        return (start, end == 0 ? start : end)
    }
    
    /// Convert period code to a 1-based row index.
    /// Schedule: D1(1) D2(2) D3(3) D4(4) DN(5,noon) D5(6) D6(7) D7(8) D8(9) D9(10) D10(11)
    static func periodToNumber(_ code: String) -> Int {
        switch code.uppercased() {
        case "D1":  return 1
        case "D2":  return 2
        case "D3":  return 3
        case "D4":  return 4
        case "DN":  return 5   // noon break
        case "D5":  return 6
        case "D6":  return 7
        case "D7":  return 8
        case "D8":  return 9
        case "D9":  return 10
        case "D10": return 11
        default:
            // Fallback: strip leading "D" and parse integer
            let cleaned = code.uppercased().replacingOccurrences(of: "D", with: "")
            return Int(cleaned) ?? 0
        }
    }
}

// Estu-specific course model
nonisolated struct EstuCourse: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let code: String
    let instructor: String
    let credits: Int
    let semester: String
    let department: String
    let courseType: CourseType
    let schedules: [EstuScheduleSlot]  // Up to 3 time slots
    let notes: String?
    let outline: CourseOutlineDetails?
    
    enum CourseType: String, Sendable, Hashable {
        case required = "必"
        case elective = "選"
        case unknown = ""
    }
    
    /// Convert to main Course models — one Course per schedule slot
    func toCourses(color: String = "#007AFF", outline: CourseOutlineDetails? = nil) -> [Course] {
        let resolvedOutline = outline ?? self.outline
        // Filter to slots that have a valid day
        let validSlots = schedules.filter { $0.dayOfWeekNumber > 0 }
        
        if validSlots.isEmpty {
            // No valid schedule, return a single course with defaults
            return [Course(
                id: id,
                name: name,
                code: code,
                instructor: instructor,
                credits: credits,
                semester: semester,
                department: department,
                courseType: Course.CourseType(rawValue: courseType.rawValue) ?? .unknown,
                dayOfWeek: "",
                startPeriod: 0,
                endPeriod: 0,
                location: schedules.first?.classroom ?? "",
                weeks: schedules.first?.weeks ?? "全",
                notes: notes,
                outline: resolvedOutline,
                color: color
            )]
        }
        
        return validSlots.enumerated().map { index, slot in
            Course(
                id: validSlots.count > 1 ? "\(id)_\(index)" : id,
                name: name,
                code: code,
                instructor: instructor,
                credits: credits,
                semester: semester,
                department: department,
                courseType: Course.CourseType(rawValue: courseType.rawValue) ?? .unknown,
                dayOfWeek: slot.dayOfWeek,
                startPeriod: slot.startPeriod,
                endPeriod: slot.endPeriod,
                location: slot.classroom,
                weeks: slot.weeks,
                notes: notes,
                outline: resolvedOutline,
                color: color
            )
        }
    }

    func withOutline(_ outline: CourseOutlineDetails?) -> EstuCourse {
        EstuCourse(
            id: id,
            name: name,
            code: code,
            instructor: instructor,
            credits: credits,
            semester: semester,
            department: department,
            courseType: courseType,
            schedules: schedules,
            notes: notes,
            outline: outline
        )
    }
}
