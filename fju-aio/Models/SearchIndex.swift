import Foundation

// MARK: - Search Result Kind

enum SearchResultKind {
    case module(AppModule)
    case course(Course)
    case classroom(roomCode: String)
    case campusBuilding(CampusBuilding)
    case campusAmenity(CampusAmenity)
    case calendarEvent(CalendarEvent)
    case assignment(Assignment)
    case guideTopic(GuideTopic)
    case regulation(Regulation)
    case emergencyContact(EmergencyContact)
    case departmentContact(DepartmentContact)
}

// MARK: - Search Result

struct SearchResult: Identifiable {
    let id: String
    let kind: SearchResultKind
    let title: String
    let subtitle: String
    let icon: String
    let score: Double
}

// MARK: - Search Engine

struct SearchEngine {

    // MARK: Field weights
    private static let weightTitleExact: Double    = 1.00
    private static let weightTitlePrefix: Double   = 0.90
    private static let weightTitleContains: Double = 0.80
    private static let weightKeyword: Double       = 0.65
    private static let weightSubtitle: Double      = 0.50
    private static let weightFullText: Double      = 0.30

    // MARK: Recency boosts
    private static let boostAssignmentDue7Days: Double    = 1.5
    private static let boostCalendarEvent14Days: Double   = 1.3

    // MARK: Type priority (used as tie-break; lower = higher priority)
    private static func typePriority(_ kind: SearchResultKind) -> Int {
        switch kind {
        case .module:              return 0
        case .course:              return 1
        case .assignment:          return 2
        case .calendarEvent:       return 3
        case .classroom:           return 4
        case .campusBuilding:      return 5
        case .campusAmenity:       return 6
        case .guideTopic:          return 7
        case .regulation:          return 8
        case .emergencyContact:    return 9
        case .departmentContact:   return 10
        }
    }

    // MARK: - Main Search

    func search(
        query: String,
        courses: [Course],
        assignments: [Assignment],
        calendarEvents: [CalendarEvent],
        checkInEnabled: Bool
    ) -> [SearchResult] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        var results: [SearchResult] = []

        // 1. App modules
        results += searchModules(q: q, checkInEnabled: checkInEnabled)

        // 2. Courses
        results += searchCourses(q: q, courses: courses)

        // 3. Classrooms (derived from courses)
        results += searchClassrooms(q: q, courses: courses)

        // 4. Campus buildings and amenities
        results += searchCampusBuildings(q: q)
        results += searchCampusAmenities(q: q)

        // 5. Calendar events
        results += searchCalendarEvents(q: q, events: calendarEvents)

        // 5. Assignments / todos
        results += searchAssignments(q: q, assignments: assignments)

        // 6. Student guide topics
        results += searchGuideTopics(q: q)

        // 7. Regulations
        results += searchRegulations(q: q)

        // 8. Contact info
        results += searchContacts(q: q)

        // Sort: descending score, then type priority as tie-break
        results.sort {
            if abs($0.score - $1.score) > 0.001 {
                return $0.score > $1.score
            }
            return Self.typePriority($0.kind) < Self.typePriority($1.kind)
        }

        return Array(results.prefix(40))
    }

    // MARK: - Module Search

    private func searchModules(q: String, checkInEnabled: Bool) -> [SearchResult] {
        ModuleRegistry.allModules
            .filter { !$0.isHidden || (checkInEnabled && $0.id == "checkIn") }
            .compactMap { module in
                let score = fieldScore(q: q,
                                       primary: module.name,
                                       secondary: module.category.rawValue,
                                       keywords: [])
                guard score > 0 else { return nil }
                return SearchResult(
                    id: "module-\(module.id)",
                    kind: .module(module),
                    title: module.name,
                    subtitle: module.category.rawValue,
                    icon: module.icon,
                    score: score
                )
            }
    }

    // MARK: - Course Search

    private func searchCourses(q: String, courses: [Course]) -> [SearchResult] {
        // Deduplicate by course id (same course may appear multiple times for multi-slot)
        var seen = Set<String>()
        return courses.compactMap { course in
            guard seen.insert(course.id).inserted else { return nil }
            let score = fieldScore(
                q: q,
                primary: course.name,
                secondary: "\(course.instructor) \(course.location) \(course.department)",
                keywords: [course.code]
            )
            guard score > 0 else { return nil }
            let subtitle = [course.instructor, course.location]
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
            return SearchResult(
                id: "course-\(course.id)",
                kind: .course(course),
                title: course.name,
                subtitle: subtitle,
                icon: "calendar",
                score: score
            )
        }
    }

    // MARK: - Classroom Search

    private func searchClassrooms(q: String, courses: [Course]) -> [SearchResult] {
        // Collect unique non-empty room codes from courses
        let rooms = Set(courses.map(\.location).filter { !$0.isEmpty })
        return rooms.compactMap { room in
            let score = fieldScore(q: q, primary: room, secondary: "", keywords: [])
            guard score > 0 else { return nil }
            return SearchResult(
                id: "classroom-\(room)",
                kind: .classroom(roomCode: room),
                title: room,
                subtitle: "教室 · 查看課表或地圖",
                icon: "door.left.hand.open",
                score: score
            )
        }
    }

    // MARK: - Campus Building Search

    private func searchCampusBuildings(q: String) -> [SearchResult] {
        CampusBuildingRegistry.all.compactMap { building in
            let score = fieldScore(q: q, primary: building.name, secondary: building.code, keywords: [])
            guard score > 0 else { return nil }
            return SearchResult(
                id: "building-\(building.code)",
                kind: .campusBuilding(building),
                title: building.name,
                subtitle: "大樓 \(building.code) · 校園地圖",
                icon: "building.2.fill",
                score: score
            )
        }
    }

    // MARK: - Campus Amenity Search

    private func searchCampusAmenities(q: String) -> [SearchResult] {
        CampusAmenity.all.compactMap { amenity in
            let score = fieldScore(
                q: q,
                primary: amenity.name,
                secondary: amenity.category.title,
                keywords: []
            )
            guard score > 0 else { return nil }
            return SearchResult(
                id: "amenity-\(amenity.id)",
                kind: .campusAmenity(amenity),
                title: amenity.name,
                subtitle: amenity.category.title,
                icon: amenity.category.iconName,
                score: score
            )
        }
    }

    // MARK: - Calendar Event Search

    private func searchCalendarEvents(q: String, events: [CalendarEvent]) -> [SearchResult] {
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "zh_TW")

        return events.compactMap { event in
            let categoryName = event.category.rawValue
            let score = fieldScore(
                q: q,
                primary: event.title,
                secondary: categoryName,
                keywords: []
            )
            guard score > 0 else { return nil }

            // Apply recency boost for upcoming events within 14 days
            var boost = 1.0
            if event.startDate > now,
               event.startDate.timeIntervalSince(now) < 14 * 86400 {
                boost = Self.boostCalendarEvent14Days
            }

            let dateStr = formatter.string(from: event.startDate)
            return SearchResult(
                id: "event-\(event.id)",
                kind: .calendarEvent(event),
                title: event.title,
                subtitle: "\(dateStr) · \(categoryName)",
                icon: "calendar.badge.clock",
                score: score * boost
            )
        }
    }

    // MARK: - Assignment Search

    private func searchAssignments(q: String, assignments: [Assignment]) -> [SearchResult] {
        let now = Date()
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_TW")
        formatter.unitsStyle = .short

        return assignments.compactMap { assignment in
            let score = fieldScore(
                q: q,
                primary: assignment.title,
                secondary: assignment.courseName,
                keywords: []
            )
            guard score > 0 else { return nil }

            // Apply recency boost for upcoming deadlines
            var boost = 1.0
            if assignment.dueDate > now,
               assignment.dueDate.timeIntervalSince(now) < 7 * 86400 {
                boost = Self.boostAssignmentDue7Days
            }

            let dueDateStr = formatter.localizedString(for: assignment.dueDate, relativeTo: now)
            return SearchResult(
                id: "assignment-\(assignment.id)",
                kind: .assignment(assignment),
                title: assignment.title,
                subtitle: "\(assignment.courseName) · \(dueDateStr)",
                icon: "checklist",
                score: score * boost
            )
        }
    }

    // MARK: - Guide Topic Search

    private func searchGuideTopics(q: String) -> [SearchResult] {
        allGuideTopics.compactMap { topic in
            let score = fieldScore(
                q: q,
                primary: topic.title,
                secondary: "\(topic.category) \(topic.summary)",
                keywords: topic.keywords
            )
            guard score > 0 else { return nil }
            return SearchResult(
                id: "guide-\(topic.id)",
                kind: .guideTopic(topic),
                title: topic.title,
                subtitle: topic.category,
                icon: topic.icon,
                score: score
            )
        }
    }

    // MARK: - Regulation Search

    private func searchRegulations(q: String) -> [SearchResult] {
        RegulationIndex.all.compactMap { reg in
            let score = fieldScore(
                q: q,
                primary: reg.title,
                secondary: reg.office.rawValue,
                keywords: reg.keywords
            )
            guard score > 0 else { return nil }
            return SearchResult(
                id: "reg-\(reg.id)",
                kind: .regulation(reg),
                title: reg.title,
                subtitle: reg.office.rawValue,
                icon: "doc.text.magnifyingglass",
                score: score
            )
        }
    }

    // MARK: - Contact Search

    private func searchContacts(q: String) -> [SearchResult] {
        var results: [SearchResult] = []

        // Emergency contacts
        for contact in allEmergencyContacts {
            let score = fieldScore(q: q, primary: contact.name, secondary: contact.phone, keywords: [])
            if score > 0 {
                results.append(SearchResult(
                    id: "emergency-\(contact.id)",
                    kind: .emergencyContact(contact),
                    title: contact.name,
                    subtitle: contact.phone,
                    icon: "phone.fill",
                    score: score
                ))
            }
        }

        // Department contacts
        for dept in allDepartmentContacts {
            let phonesJoined = dept.phones.joined(separator: " ")
            let score = fieldScore(
                q: q,
                primary: dept.name,
                secondary: "\(phonesJoined) \(dept.email ?? "")",
                keywords: []
            )
            if score > 0 {
                let subtitle = dept.phones.first ?? (dept.email ?? "")
                results.append(SearchResult(
                    id: "dept-\(dept.id)",
                    kind: .departmentContact(dept),
                    title: dept.name,
                    subtitle: subtitle,
                    icon: "building.2.fill",
                    score: score
                ))
            }
        }

        return results
    }

    // MARK: - Scoring Helper

    /// Returns a relevance score [0, 1] for a query against a result's fields.
    private func fieldScore(q: String, primary: String, secondary: String, keywords: [String]) -> Double {
        var best: Double = 0

        // Exact title match
        if primary.localizedCaseInsensitiveCompare(q) == .orderedSame {
            best = max(best, Self.weightTitleExact)
        }

        // Title starts with query
        if primary.localizedCaseInsensitiveContains(q) {
            if primary.lowercased().hasPrefix(q.lowercased()) {
                best = max(best, Self.weightTitlePrefix)
            } else {
                best = max(best, Self.weightTitleContains)
            }
        }

        // Keyword match
        for kw in keywords {
            if kw.localizedCaseInsensitiveContains(q) || q.localizedCaseInsensitiveContains(kw) {
                best = max(best, Self.weightKeyword)
            }
        }

        // Secondary field match
        if !secondary.isEmpty && secondary.localizedCaseInsensitiveContains(q) {
            best = max(best, Self.weightSubtitle)
        }

        return best
    }
}


