@preconcurrency import ActivityKit
import Foundation

nonisolated struct CourseActivityAttributes: ActivityAttributes {
    let courseName: String
    let courseId: String
    let location: String
    let instructor: String

    nonisolated struct ContentState: Codable, Hashable {
        var phase: CoursePhase
        var classStartDate: Date
        var classEndDate: Date
    }
}

nonisolated enum CoursePhase: String, Codable, Hashable {
    case before  // counting down to start
    case during  // counting down to end
    case ended   // class finished
}
