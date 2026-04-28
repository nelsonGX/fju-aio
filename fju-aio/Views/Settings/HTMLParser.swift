import Foundation
import os.log

final class HTMLParser: Sendable {
    nonisolated static let shared = HTMLParser()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.fju.aio", category: "HTMLParser")
    
    private init() {}
    
    // MARK: - ViewState Extraction
    
    nonisolated func extractViewState(from html: String) throws -> EstuViewState {
        guard let viewState = extractValue(from: html, pattern: #"name="__VIEWSTATE"[^>]*value="([^"]+)""#),
              let viewStateGenerator = extractValue(from: html, pattern: #"name="__VIEWSTATEGENERATOR"[^>]*value="([^"]+)""#),
              let eventValidation = extractValue(from: html, pattern: #"name="__EVENTVALIDATION"[^>]*value="([^"]+)""#) else {
            throw EstuError.viewStateNotFound
        }
        
        return EstuViewState(
            viewState: viewState,
            viewStateGenerator: viewStateGenerator,
            eventValidation: eventValidation
        )
    }
    
    // MARK: - Student Info Extraction
    
    nonisolated func extractStudentInfo(from html: String) -> (studentId: String?, name: String?, className: String?, totalCredits: String?)? {
        let studentId = extractSpanValue(from: html, id: "LabStuno1")
        let name = extractSpanValue(from: html, id: "LabStucna1")
        let className = extractSpanValue(from: html, id: "LabDptno1")
        let totalCredits = extractSpanValue(from: html, id: "LabTotNum1")
        
        return (studentId, name, className, totalCredits)
    }
    
    // MARK: - Course Extraction
    
    nonisolated func extractCourses(from html: String, semester: String) throws -> [EstuCourse] {
        var courses: [EstuCourse] = []
        
        logger.info("🔍 Looking for GV_NewSellist table in HTML (length: \(html.count, privacy: .public))")
        
        guard let tableRange = html.range(of: #"<table[^>]*id="GV_NewSellist"[^>]*>"#, options: .regularExpression) else {
            logger.error("❌ GV_NewSellist table NOT found in HTML")
            return []
        }
        logger.info("✅ Found GV_NewSellist table")
        
        // Find the matching </table> accounting for nested tables
        let tableStart = tableRange.upperBound
        let tableEnd = findMatchingClose(in: html, from: tableStart, open: "<table", close: "</table>")
        
        let tableHTML = String(html[tableStart..<tableEnd])
        logger.info("📊 Table HTML length: \(tableHTML.count, privacy: .public)")
        
        // Extract top-level <tr> rows with depth-aware parsing (handles nested tables)
        let rows = extractTopLevelRows(from: tableHTML)
        
        logger.info("📋 Found \(rows.count, privacy: .public) top-level <tr> rows (first is header)")
        
        for (index, rowHTML) in rows.dropFirst().enumerated() {
            let cells = extractTableCells(from: rowHTML)
            
            // Main row: first cell is a number (NO). Skip sub-rows.
            let firstCell = cells.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let isMainRow = !firstCell.isEmpty && firstCell.allSatisfy(\.isNumber)
            
            if !isMainRow {
                logger.info("⏭️ Row \(index, privacy: .public): skipping (first cell='\(firstCell.prefix(20), privacy: .public)', not a number)")
                continue
            }
            
            logger.info("🔄 Row \(index, privacy: .public): main row, \(cells.count, privacy: .public) cells")
            
            if let course = parseCourseRow(cells: cells, rowHTML: rowHTML, semester: semester) {
                let slotDescs = course.schedules.map { "\($0.dayOfWeek) \($0.periods) \($0.classroom)" }.joined(separator: " | ")
                logger.info("✅ Row \(index, privacy: .public): \(course.name, privacy: .public) [\(slotDescs, privacy: .public)]")
                courses.append(course)
            } else {
                logger.warning("⚠️ Row \(index, privacy: .public): parseCourseRow returned nil")
            }
        }
        
        logger.info("📚 Total parsed courses: \(courses.count, privacy: .public)")
        return courses
    }
    
    private nonisolated func parseCourseRow(cells: [String], rowHTML: String, semester: String) -> EstuCourse? {
        // Table has 27 columns (0-26):
        // [0] NO, [1] 課程標記, [2] 學年度, [3] 學期, [4] 課程代碼,
        // [5] 主開課程碼, [6] 開課單位名稱, [7] 科目名稱,
        // [8] 學分, [9] 開課選別, [10] 學生選課設定選別, [11] 期次, [12] 授課教師,
        // [13] 星期(1), [14] 週別(1), [15] 節次(1), [16] 教室(1),
        // [17] 星期(2), [18] 週別(2), [19] 節次(2), [20] 教室(2),
        // [21] 星期(3), [22] 週別(3), [23] 節次(3), [24] 教室(3),
        // [25] 通識領域, [26] 備註
        guard cells.count >= 17 else {
            logger.warning("  ❌ Not enough cells: \(cells.count, privacy: .public) < 17")
            return nil
        }
        
        let year = cleanCell(cells[2])
        let sem = cleanCell(cells[3])
        let courseCode = cleanCell(cells[4])
        let department = cleanCell(cells[6])
        let creditsStr = cleanCell(cells[8])
        let typeStr = cleanCell(cells[9])
        let instructor = cleanCell(cells[12])
        let notes = cells.count > 26 ? cleanCell(cells[26]) : nil
        
        logger.info("  📝 courseCode=\(courseCode, privacy: .public) dept=\(department, privacy: .public) credits=\(creditsStr, privacy: .public) type=\(typeStr, privacy: .public) instructor=\(instructor, privacy: .public)")
        
        guard !courseCode.isEmpty else {
            logger.warning("  ❌ courseCode is empty, skipping row")
            return nil
        }
        
        // Extract course name from the nested span (GV_NewSellist_Lab_Coucna_N), or fall back to cell [7]
        let spanName = extractCourseName(from: rowHTML)
        let fallbackName = cleanCell(cells[7])
        let courseName = spanName ?? fallbackName
        logger.info("  📝 name=\(courseName, privacy: .public)")
        
        let credits = Int(creditsStr.replacingOccurrences(of: ".00", with: "").replacingOccurrences(of: ".0", with: "")) ?? 0
        let courseType = EstuCourse.CourseType(rawValue: typeStr) ?? .unknown
        
        // Extract up to 3 schedule slots: [13-16], [17-20], [21-24]
        var schedules: [EstuScheduleSlot] = []
        for slotIndex in 0..<3 {
            let base = 13 + slotIndex * 4
            guard cells.count > base + 3 else { break }
            
            let day = cleanCell(cells[base])
            let weeks = cleanCell(cells[base + 1])
            let periods = cleanCell(cells[base + 2])
            let classroom = cleanCell(cells[base + 3])
            
            // A slot is valid if it has a meaningful day or period (not empty/nbsp)
            if !day.isEmpty || !periods.isEmpty {
                logger.info("  📅 Slot \(slotIndex, privacy: .public): day=\(day, privacy: .public) weeks=\(weeks, privacy: .public) periods=\(periods, privacy: .public) classroom=\(classroom, privacy: .public)")
                schedules.append(EstuScheduleSlot(
                    dayOfWeek: day,
                    weeks: weeks,
                    periods: periods,
                    classroom: classroom
                ))
            }
        }
        
        let actualSemester = !year.isEmpty && !sem.isEmpty ? "\(year)-\(sem)" : semester
        
        return EstuCourse(
            id: courseCode,
            name: courseName.isEmpty ? courseCode : courseName,
            code: courseCode,
            instructor: instructor,
            credits: credits,
            semester: actualSemester,
            department: department,
            courseType: courseType,
            schedules: schedules,
            notes: notes?.isEmpty == false ? notes : nil,
            outline: nil
        )
    }
    
    /// Clean a cell value: trim whitespace and treat &nbsp; as empty
    private nonisolated func cleanCell(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "&nbsp;" || trimmed == "\u{00A0}" {
            return ""
        }
        return trimmed.replacingOccurrences(of: "&nbsp;", with: "").replacingOccurrences(of: "\u{00A0}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Extract course name from the span with id like "GV_NewSellist_Lab_Coucna_N"
    private nonisolated func extractCourseName(from rowHTML: String) -> String? {
        let pattern = #"id="GV_NewSellist_Lab_Coucna_\d+"[^>]*>(.*?)</span>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: rowHTML, range: NSRange(rowHTML.startIndex..., in: rowHTML)),
              let range = Range(match.range(at: 1), in: rowHTML) else {
            return nil
        }
        return stripHTMLTags(String(rowHTML[range])).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Helper Methods
    
    private nonisolated func extractValue(from html: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return String(html[range])
    }
    
    private nonisolated func extractSpanValue(from html: String, id: String) -> String? {
        let pattern = #"<span[^>]*id="\#(id)"[^>]*>(.*?)</span>"#
        return extractValue(from: html, pattern: pattern)
    }
    
    /// Find the matching closing tag accounting for nested open/close pairs.
    /// Returns the index of the start of the closing tag (e.g. the `<` in `</table>`).
    private nonisolated func findMatchingClose(in html: String, from start: String.Index, open: String, close: String) -> String.Index {
        var depth = 1
        var cursor = start
        while cursor < html.endIndex && depth > 0 {
            let remaining = html[cursor...]
            let nextOpen = remaining.range(of: open, options: .caseInsensitive)
            let nextClose = remaining.range(of: close, options: .caseInsensitive)
            
            if let closeRange = nextClose, (nextOpen == nil || closeRange.lowerBound <= nextOpen!.lowerBound) {
                depth -= 1
                if depth == 0 {
                    return closeRange.lowerBound
                }
                cursor = closeRange.upperBound
            } else if let openRange = nextOpen {
                depth += 1
                cursor = openRange.upperBound
            } else {
                break
            }
        }
        return html.endIndex
    }
    
    /// Extract top-level <tr> row contents from table HTML, handling nested tables.
    private nonisolated func extractTopLevelRows(from tableHTML: String) -> [String] {
        var rows: [String] = []
        var cursor = tableHTML.startIndex
        let openPattern = try? NSRegularExpression(pattern: #"<tr[^>]*>"#, options: [.caseInsensitive])
        
        while cursor < tableHTML.endIndex {
            let remaining = NSRange(cursor..., in: tableHTML)
            guard let openMatch = openPattern?.firstMatch(in: tableHTML, range: remaining),
                  let openRange = Range(openMatch.range, in: tableHTML) else { break }
            
            let contentStart = openRange.upperBound
            // Walk forward counting nested <tr></tr> to find the matching </tr>
            var depth = 1
            var inner = contentStart
            while inner < tableHTML.endIndex && depth > 0 {
                let rest = tableHTML[inner...]
                let nextOpen = rest.range(of: "<tr", options: .caseInsensitive)
                let nextClose = rest.range(of: "</tr>", options: .caseInsensitive)
                
                if let close = nextClose, (nextOpen == nil || close.lowerBound <= nextOpen!.lowerBound) {
                    depth -= 1
                    if depth == 0 {
                        rows.append(String(tableHTML[contentStart..<close.lowerBound]))
                    }
                    inner = close.upperBound
                } else if let open = nextOpen {
                    depth += 1
                    inner = open.upperBound
                } else {
                    break
                }
            }
            cursor = inner
        }
        return rows
    }
    
    /// Extract top-level table cells, handling nested tables correctly
    private nonisolated func extractTableCells(from rowHTML: String) -> [String] {
        var cells: [String] = []
        var searchStart = rowHTML.startIndex
        
        let openTag = try? NSRegularExpression(pattern: #"<td[^>]*>"#, options: [.caseInsensitive])
        let closeTag = "</td>"
        
        while searchStart < rowHTML.endIndex {
            // Find next <td...> opening tag
            let remaining = NSRange(searchStart..., in: rowHTML)
            guard let openMatch = openTag?.firstMatch(in: rowHTML, range: remaining) else { break }
            guard let openRange = Range(openMatch.range, in: rowHTML) else { break }
            
            // Start content after the opening tag
            let contentStart = openRange.upperBound
            var depth = 1
            var cursor = contentStart
            
            // Walk through the HTML counting nested <td> open/close to find the matching </td>
            while cursor < rowHTML.endIndex && depth > 0 {
                let remainingStr = rowHTML[cursor...]
                
                // Find next <td or </td>
                let nextOpen = remainingStr.range(of: "<td", options: .caseInsensitive)
                let nextClose = remainingStr.range(of: closeTag, options: .caseInsensitive)
                
                if let close = nextClose, (nextOpen == nil || close.lowerBound <= nextOpen!.lowerBound) {
                    depth -= 1
                    if depth == 0 {
                        let cellContent = String(rowHTML[contentStart..<close.lowerBound])
                        cells.append(stripHTMLTags(cellContent))
                    }
                    cursor = close.upperBound
                } else if let open = nextOpen {
                    depth += 1
                    cursor = open.upperBound
                } else {
                    break
                }
            }
            
            searchStart = cursor
        }
        
        return cells
    }
    
    private nonisolated func stripHTMLTags(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Error Detection
    
    nonisolated func containsLoginError(in html: String) -> Bool {
        html.contains("帳號或密碼錯誤") || html.contains("登入失敗")
    }
    
    /// Check if the response indicates the session has expired (redirected back to login page without student info)
    nonisolated func containsSessionError(in html: String) -> Bool {
        // If page has the login form (TxtLdapId) but no student info, session has expired
        let hasLoginForm = html.contains("TxtLdapId") && html.contains("ButLogin")
        let hasStudentInfo = html.contains("LabStucna1") || html.contains("LabStuno1")
        let hasSessionExpiredText = html.contains("Session") && html.contains("過期")
        
        let isError = (hasLoginForm && !hasStudentInfo) || hasSessionExpiredText
        logger.info("🔍 containsSessionError: hasLoginForm=\(hasLoginForm, privacy: .public) hasStudentInfo=\(hasStudentInfo, privacy: .public) hasSessionExpiredText=\(hasSessionExpiredText, privacy: .public) → \(isError, privacy: .public)")
        return isError
    }
}
