import Foundation

final class NetworkService: Sendable {
    nonisolated static let shared = NetworkService()
    private let logger = NetworkLogger.shared
    
    private init() {}
    
    nonisolated func performRequest(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        logger.logRequest(request)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            logger.logResponse(response, data: data, error: nil)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse
            }
            
            return (data, httpResponse)
        } catch {
            logger.logResponse(nil, data: nil, error: error)
            throw NetworkError.connectionFailed(error)
        }
    }
}

nonisolated enum NetworkError: LocalizedError {
    case invalidResponse
    case connectionFailed(Error)
    case httpError(Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "伺服器回應無效"
        case .connectionFailed(let error): return "連線失敗: \(error.localizedDescription)"
        case .httpError(let code): return "HTTP 錯誤: \(code)"
        }
    }
}
