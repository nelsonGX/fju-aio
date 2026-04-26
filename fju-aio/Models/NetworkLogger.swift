import Foundation
import os.log

final class NetworkLogger {
    static let shared = NetworkLogger()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.fju.aio", category: "Network")
    
    private init() {}
    
    func logRequest(_ request: URLRequest) {
        logger.info("🌐 REQUEST: \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "unknown")")
        if let headers = request.allHTTPHeaderFields {
            logger.debug("📋 Headers: \(headers)")
        }
        if let body = request.httpBody, let bodyString = String(data: body, encoding: .utf8) {
            logger.debug("📦 Body: \(bodyString)")
        }
    }
    
    func logResponse(_ response: URLResponse?, data: Data?, error: Error?) {
        if let error = error {
            logger.error("❌ ERROR: \(error.localizedDescription)")
            return
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            logger.warning("⚠️ Invalid response type")
            return
        }
        
        let statusEmoji = httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 ? "✅" : "❌"
        logger.info("\(statusEmoji) RESPONSE: \(httpResponse.statusCode) \(httpResponse.url?.absoluteString ?? "")")
        
        if let headers = httpResponse.allHeaderFields as? [String: String] {
            logger.debug("📋 Response Headers: \(headers)")
        }
        
        if let data = data, let bodyString = String(data: data, encoding: .utf8) {
            logger.debug("📦 Response Body: \(bodyString)")
        }
    }
}
