import Foundation
import os.log

actor ClassroomScheduleService {
    static let shared = ClassroomScheduleService()

    private let remoteURL = URL(string: "https://github.com/FJU-Devs/fju-classroom-schedule/raw/refs/heads/main/fju_day_courses.json")!
    private let networkService = NetworkService.shared
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.nelsongx.apps.fju-aio", category: "ClassroomSchedule")
    private var cachedIndex: ClassroomScheduleIndex?

    private init() {}

    func clearInMemoryCache() {
        cachedIndex = nil
    }

    func loadIndex(forceRefresh: Bool = false) async throws -> ClassroomScheduleIndex {
        if !forceRefresh, let cachedIndex {
            return cachedIndex
        }

        let dataURL = cacheFileURL()
        let data: Data

        if !forceRefresh, FileManager.default.fileExists(atPath: dataURL.path) {
            logger.info("Loading classroom schedule JSON from disk cache")
            data = try Data(contentsOf: dataURL, options: [.mappedIfSafe])
        } else {
            logger.info("Downloading classroom schedule JSON")
            data = try await downloadJSON()
            try data.write(to: dataURL, options: [.atomic])
        }

        let payload = try JSONDecoder().decode(ClassroomSchedulePayload.self, from: data)
        let index = buildIndex(from: payload)
        cachedIndex = index
        logger.info("Built classroom schedule index: rooms=\(index.rooms.count, privacy: .public), courses=\(payload.courses.count, privacy: .public)")
        return index
    }

    private func downloadJSON() async throws -> Data {
        var request = URLRequest(url: remoteURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, httpResponse) = try await networkService.performRequest(request, retryPolicy: .idempotent(maxRetries: 3))
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func cacheFileURL() -> URL {
        let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let directory = cachesDirectory.appendingPathComponent("ClassroomSchedule", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("fju_day_courses.json")
    }

    private func buildIndex(from payload: ClassroomSchedulePayload) -> ClassroomScheduleIndex {
        var rooms = Set<String>()
        var schedulesByDay: [String: [String: [String: [ClassroomScheduledCourse]]]] = [:]

        for weekday in ClassroomScheduleConstants.weekdays {
            schedulesByDay[weekday] = [:]
        }

        for record in payload.courses {
            let slots = [
                (week: record.week1, weekday: record.weekday1, period: record.period1, room: record.room1),
                (week: record.week2, weekday: record.weekday2, period: record.period2, room: record.room2),
                (week: record.week3, weekday: record.weekday3, period: record.period3, room: record.room3)
            ]

            for (slotIndex, slot) in slots.enumerated() {
                let weekday = slot.weekday.trimmingCharacters(in: .whitespacesAndNewlines)
                let room = ClassroomScheduleConstants.normalizedRoom(slot.room)
                let periods = ClassroomScheduleConstants.expandPeriods(slot.period)

                guard !weekday.isEmpty, !room.isEmpty, !periods.isEmpty else {
                    continue
                }

                rooms.insert(room)

                for period in periods {
                    let course = ClassroomScheduledCourse(
                        id: "\(record.rowNo)-\(record.courseCode)-\(slotIndex)-\(weekday)-\(period)-\(room)",
                        courseCode: record.courseCode,
                        courseName: record.courseName,
                        offeringUnit: record.offeringUnit,
                        instructor: ClassroomScheduleConstants.sanitizedInstructor(record.instructor),
                        week: slot.week.trimmingCharacters(in: .whitespacesAndNewlines),
                        room: room,
                        weekday: weekday,
                        period: period,
                        remarks: record.remarks
                    )

                    var dayMap = schedulesByDay[weekday] ?? [:]
                    var roomMap = dayMap[room] ?? [:]
                    var periodCourses = roomMap[period] ?? []
                    periodCourses.append(course)
                    roomMap[period] = periodCourses
                    dayMap[room] = roomMap
                    schedulesByDay[weekday] = dayMap
                }
            }
        }

        let sortedRooms = rooms.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let metadata = ClassroomScheduleMetadata(
            sourceURL: payload.sourceURL,
            division: payload.division,
            generatedAtUTC: payload.generatedAtUTC,
            courseCount: payload.courseCount,
            roomCount: sortedRooms.count
        )

        return ClassroomScheduleIndex(
            metadata: metadata,
            rooms: sortedRooms,
            schedulesByDay: schedulesByDay
        )
    }
}
