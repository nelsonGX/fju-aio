import Foundation
import os.log

// MARK: - GroupRollcallService
// Performs rollcall check-in using a friend's LDAP credentials
// that were received via a scanned QR code.
//
// Privacy model:
// - Credentials come directly from a QR the friend intentionally showed
// - They are NEVER stored (only held in memory for the duration of check-in)
// - They are NEVER sent to any server other than the school's own TronClass API
// - The user was warned via the QR generation UI that sharing carries risk

actor GroupRollcallService {
    static let shared = GroupRollcallService()

    private let baseURL = "https://elearn2.fju.edu.tw"
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.nelsongx.apps.fju-aio", category: "GroupRollcall")

    private init() {}

    // MARK: - Authenticate with friend's credentials (one-shot, no storage)

    /// Authenticates using a friend's LDAP credentials and returns a TronClass session.
    /// Credentials are NEVER saved to keychain — the full CAS flow is replicated here
    /// without touching CredentialStore.
    func authenticateWithCredentials(username: String, password: String) async throws -> TronClassSession {
        let baseURL = "https://elearn2.fju.edu.tw"

        // Step 1: Get TGT
        let tgtURL = URL(string: "\(baseURL)/cas/v1/tickets")!
        var tgtReq = URLRequest(url: tgtURL)
        tgtReq.httpMethod = "POST"
        tgtReq.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        tgtReq.setValue("*/*", forHTTPHeaderField: "Accept")
        tgtReq.setValue("TronClass/2.14.5 (iPhone; iOS 18.2; Scale/3.00)", forHTTPHeaderField: "User-Agent")
        let encodedUser = username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedPass = password.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        tgtReq.httpBody = "username=\(encodedUser)&password=\(encodedPass)".data(using: .utf8)

        let (_, tgtResp) = try await URLSession.shared.data(for: tgtReq)
        guard let tgtHTTP = tgtResp as? HTTPURLResponse, tgtHTTP.statusCode == 201,
              let location = tgtHTTP.value(forHTTPHeaderField: "Location"),
              let tgt = location.components(separatedBy: "/").last else {
            throw AuthenticationError.invalidCredentials
        }

        // Step 2: Get Service Ticket
        let stURL = URL(string: "\(baseURL)/cas/v1/tickets/\(tgt)")!
        var stReq = URLRequest(url: stURL)
        stReq.httpMethod = "POST"
        stReq.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        stReq.setValue("*/*", forHTTPHeaderField: "Accept")
        stReq.setValue("TronClass/2.14.5 (iPhone; iOS 18.2; Scale/3.00)", forHTTPHeaderField: "User-Agent")
        stReq.httpBody = "service=https://elearn2.fju.edu.tw/api/cas-login".data(using: .utf8)

        let (stData, stResp) = try await URLSession.shared.data(for: stReq)
        guard let stHTTP = stResp as? HTTPURLResponse, stHTTP.statusCode == 200,
              let serviceTicket = String(data: stData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw AuthenticationError.serviceTicketInvalid
        }

        // Step 3: Exchange for Session
        var components = URLComponents(string: "\(baseURL)/api/cas-login")!
        components.queryItems = [URLQueryItem(name: "ticket", value: serviceTicket)]
        var sessionReq = URLRequest(url: components.url!)
        sessionReq.httpMethod = "GET"
        sessionReq.setValue("cross-site", forHTTPHeaderField: "Sec-Fetch-Site")
        sessionReq.setValue("capacitor://localhost", forHTTPHeaderField: "Origin")
        sessionReq.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        sessionReq.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) TronClass/common",
            forHTTPHeaderField: "User-Agent"
        )

        let (sessData, sessResp) = try await URLSession.shared.data(for: sessionReq)
        guard let sessHTTP = sessResp as? HTTPURLResponse, sessHTTP.statusCode == 200,
              let sessionId = sessHTTP.value(forHTTPHeaderField: "X-SESSION-ID") else {
            throw AuthenticationError.missingSessionId
        }

        struct CASResp: Decodable { let user_id: Int }
        let parsed = try JSONDecoder().decode(CASResp.self, from: sessData)

        // Parse expiry from session ID (V2-1-{uuid}.{base64}.{timestamp_ms}.{sig})
        let parts = sessionId.components(separatedBy: ".")
        let expiresAt: Date
        if parts.count >= 3, let ts = TimeInterval(parts[2]) {
            expiresAt = Date(timeIntervalSince1970: ts / 1000)
        } else {
            expiresAt = Date().addingTimeInterval(24 * 3600)
        }

        logger.info("✅ Group auth OK for user \(parsed.user_id) — session NOT saved to keychain")
        return TronClassSession(sessionId: sessionId, userId: parsed.user_id, expiresAt: expiresAt)
    }

    // MARK: - Manual Check-In with friend's session

    func manualCheckIn(
        rollcall: Rollcall,
        numberCode: String,
        using session: TronClassSession
    ) async throws -> Bool {
        let url = URL(string: "\(baseURL)/api/rollcall/\(rollcall.rollcall_id)/answer_number_rollcall")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        applyHeaders(&request, sessionId: session.sessionId)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = ["deviceId": generateDeviceId(), "numberCode": numberCode]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return false }
        if http.statusCode == 401 || http.statusCode == 403 { throw RollcallError.sessionExpired }
        guard http.statusCode == 200 else { return false }

        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let status = json?["status"] as? String ?? ""
        logger.info("Group manual check-in result: \(status) for rollcall \(rollcall.rollcall_id)")
        return status == "on_call" || status == "late"
    }

    // MARK: - Radar Check-In with friend's session

    func radarCheckIn(
        rollcall: Rollcall,
        latitude: Double,
        longitude: Double,
        accuracy: Double,
        using session: TronClassSession
    ) async throws -> Bool {
        let url = URL(string: "\(baseURL)/api/rollcall/\(rollcall.rollcall_id)/answer")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        applyHeaders(&request, sessionId: session.sessionId)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "deviceId": generateDeviceId(),
            "latitude": latitude,
            "longitude": longitude,
            "speed": 0,
            "accuracy": accuracy,
            "altitude": 0,
            "heading": 0
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return false }
        if http.statusCode == 401 || http.statusCode == 403 { throw RollcallError.sessionExpired }
        guard http.statusCode == 200 else { return false }

        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let status = json?["status"] as? String ?? ""
        logger.info("Group radar check-in result: \(status) for rollcall \(rollcall.rollcall_id)")
        return status == "on_call" || status == "late"
    }

    // MARK: - Fetch Active Rollcalls with friend's session

    func fetchActiveRollcalls(using session: TronClassSession) async throws -> [Rollcall] {
        var components = URLComponents(string: "\(baseURL)/api/radar/rollcalls")!
        components.queryItems = [URLQueryItem(name: "api_version", value: "1.1.0")]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        applyHeaders(&request, sessionId: session.sessionId)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RollcallError.sessionExpired }
        if http.statusCode == 401 || http.statusCode == 403 { throw RollcallError.sessionExpired }

        let decoded = try JSONDecoder().decode(RollcallsResponse.self, from: data)
        logger.info("Fetched \(decoded.rollcalls.count) rollcalls for group member")
        return decoded.rollcalls
    }

    // MARK: - Helpers

    private func applyHeaders(_ request: inout URLRequest, sessionId: String) {
        request.setValue(sessionId, forHTTPHeaderField: "x-session-id")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("zh-Hant", forHTTPHeaderField: "Accept-Language")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) TronClass/common",
            forHTTPHeaderField: "User-Agent"
        )
    }

    private func generateDeviceId() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Per-member check-in result

struct GroupMemberCheckInResult: Identifiable, Sendable {
    let id: String  // friend record ID
    let displayName: String
    var status: Status

    enum Status: Sendable {
        case pending
        case authenticating
        case checking
        case success
        case failure(String)
    }

    var statusLabel: String {
        switch status {
        case .pending: return "等待中"
        case .authenticating: return "登入中..."
        case .checking: return "簽到中..."
        case .success: return "簽到成功"
        case .failure(let msg): return msg
        }
    }

    var isFinished: Bool {
        switch status {
        case .success, .failure: return true
        default: return false
        }
    }
}
