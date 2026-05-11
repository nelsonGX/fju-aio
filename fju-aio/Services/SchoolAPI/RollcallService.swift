import Foundation
import Security
import os.log

actor RollcallService {
    static let shared = RollcallService()

    private let baseURL = "https://elearn2.fju.edu.tw"
    private let authService = TronClassAuthService.shared
    private let networkService = NetworkService.shared
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.nelsongx.apps.fju-aio", category: "Rollcall")

    private init() {}

    // MARK: - Fetch Attendance History

    func fetchAttendanceRollcalls(courseId: Int, userId: Int) async throws -> [AttendanceRollcall] {
        let session = try await authService.getValidSession()

        let url = URL(string: "\(baseURL)/api/course/\(courseId)/student/\(userId)/rollcalls")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        Self.applyHeaders(&request, sessionId: session.sessionId)

        let (data, http) = try await networkService.performRequest(request, retryPolicy: .idempotent())
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

        let (data, http) = try await networkService.performRequest(request, retryPolicy: .idempotent())

        if http.statusCode == 401 || http.statusCode == 403 { throw RollcallError.sessionExpired }

        do {
            let decoded = try JSONDecoder().decode(RollcallsResponse.self, from: data)
            logger.info("✅ Fetched \(decoded.rollcalls.count) rollcalls")
            return decoded.rollcalls
        } catch {
            let rawJSON = String(data: data, encoding: .utf8) ?? "<non-UTF8>"
            logger.error("❌ Rollcall decode error: \(error, privacy: .public)\nRaw response: \(rawJSON, privacy: .private)")
            throw error
        }
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

        let (data, http) = try await networkService.performRequest(request, retryPolicy: .none)

        if http.statusCode == 401 || http.statusCode == 403 { throw RollcallError.sessionExpired }
        guard http.statusCode == 200 else {
            throw RollcallError.serverMessage(Self.rollcallFailureMessage(from: data) ?? "數字碼點名失敗")
        }

        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let status = json?["status"] as? String ?? ""
        guard status == "on_call" else {
            throw RollcallError.serverMessage(Self.rollcallFailureMessage(from: data) ?? "數字碼錯誤，請再試一次")
        }
        return true
    }

    // MARK: - Radar Check-In

    func radarCheckIn(rollcall: Rollcall, latitude: Double, longitude: Double, accuracy: Double) async throws -> Bool {
        let session = try await authService.getValidSession()

        let url = URL(string: "\(baseURL)/api/rollcall/\(rollcall.rollcall_id)/answer")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        Self.applyHeaders(&request, sessionId: session.sessionId)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any?] = [
            "deviceId":         Self.generateDeviceId(),
            "latitude":         latitude,
            "longitude":        longitude,
            "speed":            0,
            "accuracy":         accuracy,
            "altitude":         0,
            "altitudeAccuracy": nil,
            "heading":          0,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body.compactMapValues { $0 })

        let (data, http) = try await networkService.performRequest(request, retryPolicy: .none)

        if http.statusCode == 401 || http.statusCode == 403 { throw RollcallError.sessionExpired }
        guard http.statusCode == 200 else {
            throw RollcallError.serverMessage(Self.rollcallFailureMessage(from: data) ?? "雷達點名失敗")
        }

        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let status = json?["status"] as? String ?? ""
        guard status == "on_call" || status == "late" else {
            throw RollcallError.serverMessage(Self.rollcallFailureMessage(from: data) ?? "雷達點名失敗，可能不在教室範圍內")
        }
        return true
    }

    // MARK: - QR Check-In

    func qrCheckIn(rollcall: Rollcall, qrContent: String) async throws -> Bool {
        let data = try Self.parseQRData(from: qrContent)
        let session = try await authService.getValidSession()

        let url = URL(string: "\(baseURL)/api/rollcall/\(rollcall.rollcall_id)/answer_qr_rollcall")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        Self.applyHeaders(&request, sessionId: session.sessionId)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = ["data": data, "deviceId": Self.generateDeviceId()]
        request.httpBody = try JSONEncoder().encode(body)

        let (responseData, http) = try await networkService.performRequest(request, retryPolicy: .none)

        if http.statusCode == 401 || http.statusCode == 403 { throw RollcallError.sessionExpired }
        guard http.statusCode == 200 else {
            throw RollcallError.serverMessage(Self.rollcallFailureMessage(from: responseData) ?? "QR Code 點名失敗")
        }

        let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        let status = json?["status"] as? String ?? ""
        guard status == "on_call" || status == "late" else {
            throw RollcallError.serverMessage(Self.rollcallFailureMessage(from: responseData) ?? "QR Code 點名失敗，請再試一次")
        }
        return true
    }

    /// Parses the data payload from a QR code string.
    /// QR format: /j?p=0~<id>!3~<data>!4~<extra>
    /// The `data` field sent to the server is the value after "3~" up to the next "!".
    private static func parseQRData(from qrContent: String) throws -> String {
        // Split by "!" and find the segment starting with "3~"
        let segments = qrContent.split(separator: "!", omittingEmptySubsequences: true)
        for segment in segments {
            if segment.hasPrefix("3~") {
                return String(segment.dropFirst(2))
            }
        }
        throw RollcallError.invalidQRCode
    }

    private nonisolated static func rollcallFailureMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text.isEmpty ? nil : text
        }
        for key in ["message", "error", "detail", "msg"] {
            if let value = json[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        if let status = json["status"] as? String, !status.isEmpty {
            return "點名狀態：\(status)"
        }
        return nil
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
