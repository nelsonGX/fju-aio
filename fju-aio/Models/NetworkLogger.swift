import Foundation
import os.log

final class NetworkLogger: Sendable {
    nonisolated static let shared = NetworkLogger()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.fju.aio", category: "Network")
    
    private init() {}
    
    nonisolated func logRequest(_ request: URLRequest) {
        logger.info("🌐 REQUEST: \(request.httpMethod ?? "GET", privacy: .public) \(request.url?.absoluteString ?? "unknown", privacy: .public)")
        if let headers = request.allHTTPHeaderFields {
            logger.debug("📋 Headers: \(String(describing: headers), privacy: .private)")
        }
        if let body = request.httpBody, let bodyString = String(data: body, encoding: .utf8) {
            logger.debug("📦 Body: \(bodyString, privacy: .private)")
        }
    }
    
    nonisolated func logResponse(_ response: URLResponse?, data: Data?, error: Error?) {
        if let error = error {
            logger.error("❌ ERROR: \(error.localizedDescription, privacy: .public)")
            return
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            logger.warning("⚠️ Invalid response type")
            return
        }
        
        let statusEmoji = httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 ? "✅" : "❌"
        logger.info("\(statusEmoji) RESPONSE: \(httpResponse.statusCode, privacy: .public) \(httpResponse.url?.absoluteString ?? "", privacy: .public)")
        
        if let headers = httpResponse.allHeaderFields as? [String: String] {
            logger.debug("📋 Response Headers: \(String(describing: headers), privacy: .private)")
        }
        
        if let data = data, let bodyString = String(data: data, encoding: .utf8) {
            logger.debug("📦 Response Body: \(bodyString, privacy: .private)")
        }
    }
}
