import Foundation
import Security
import os.log

actor RollcallService {
    static let shared = RollcallService()

    private let baseURL = "https://elearn2.fju.edu.tw"
    private let authService = TronClassAuthService.shared
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.fju.aio", category: "Rollcall")

    private init() {}

    // MARK: - Fetch Attendance History

    func fetchAttendanceRollcalls(courseId: Int, userId: Int) async throws -> [AttendanceRollcall] {
        let session = try await authService.getValidSession()

        let url = URL(string: "\(baseURL)/api/course/\(courseId)/student/\(userId)/rollcalls")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        Self.applyHeaders(&request, sessionId: session.sessionId)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RollcallError.sessionExpired }
        if http.statusCode == 401 || http.statusCode == 403 { throw RollcallError.sessionExpired }

        let decoded = try JSONDecoder().decode(AttendanceRollcallsResponse.self, from: data)
        logger.info("✅ Fetched \(decoded.rollcalls.count) attendance rollcalls for course \(courseId)")
        return decoded.rollcalls
    }

    // MARK: - Fetch Rollcalls

    func fetchActiveRollcalls() async throws -> [Rollcall] {
        let session = try await authService.getValidSession()

        var components = URLComponents(string: "\(baseURL)/api/radar/rollcalls")!
        components.queryItems = [URLQueryItem(name: "api_version", value: "1.1.0")]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        Self.applyHeaders(&request, sessionId: session.sessionId)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RollcallError.sessionExpired }

        if http.statusCode == 401 || http.statusCode == 403 { throw RollcallError.sessionExpired }

        let decoded = try JSONDecoder().decode(RollcallsResponse.self, from: data)
        logger.info("✅ Fetched \(decoded.rollcalls.count) rollcalls")
        return decoded.rollcalls
    }

    // MARK: - Manual Check-In

    func manualCheckIn(rollcall: Rollcall, code: String) async throws -> Bool {
        let session = try await authService.getValidSession()

        let url = URL(string: "\(baseURL)/api/rollcall/\(rollcall.rollcall_id)/answer_number_rollcall")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        Self.applyHeaders(&request, sessionId: session.sessionId)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = ["deviceId": Self.generateDeviceId(), "numberCode": code]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return false }

        if http.statusCode == 401 || http.statusCode == 403 { throw RollcallError.sessionExpired }
        guard http.statusCode == 200 else { return false }

        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?["status"] as? String == "on_call"
    }

    // MARK: - Helpers

    private static func applyHeaders(_ request: inout URLRequest, sessionId: String) {
        request.setValue(sessionId, forHTTPHeaderField: "x-session-id")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("zh-Hant", forHTTPHeaderField: "Accept-Language")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) TronClass/common",
            forHTTPHeaderField: "User-Agent"
        )
    }

    private static func generateDeviceId() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
