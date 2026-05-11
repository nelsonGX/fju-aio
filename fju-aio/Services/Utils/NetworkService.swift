import Foundation

final class NetworkService: Sendable {
    nonisolated static let shared = NetworkService()
    private let logger = NetworkLogger.shared
    
    private init() {}
    
    nonisolated func performRequest(
        _ request: URLRequest,
        session: URLSession = .shared,
        retryPolicy: NetworkRetryPolicy = .automatic
    ) async throws -> (Data, HTTPURLResponse) {
        guard await MainActor.run(body: { NetworkMonitor.shared.isConnected }) else {
            throw NetworkError.offline
        }

        let resolvedRetryPolicy = retryPolicy.resolved(for: request)
        var attempt = 0

        while true {
            logger.logRequest(request)

            do {
                let (data, response) = try await session.data(for: request)
                logger.logResponse(response, data: data, error: nil)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NetworkError.invalidResponse
                }

                if resolvedRetryPolicy.shouldRetry(statusCode: httpResponse.statusCode),
                   attempt < resolvedRetryPolicy.maxRetries {
                    try await sleepBeforeRetry(attempt: attempt, response: httpResponse, policy: resolvedRetryPolicy)
                    attempt += 1
                    continue
                }

                return (data, httpResponse)
            } catch is CancellationError {
                throw CancellationError()
            } catch let urlError as URLError where urlError.code == .cancelled {
                throw CancellationError()
            } catch {
                logger.logResponse(nil, data: nil, error: error)

                guard resolvedRetryPolicy.shouldRetry(error: error),
                      attempt < resolvedRetryPolicy.maxRetries else {
                    throw NetworkError.connectionFailed(error)
                }

                try await sleepBeforeRetry(attempt: attempt, response: nil, policy: resolvedRetryPolicy)
                attempt += 1
            }
        }
    }

    private nonisolated func sleepBeforeRetry(
        attempt: Int,
        response: HTTPURLResponse?,
        policy: ResolvedNetworkRetryPolicy
    ) async throws {
        let delay = retryAfterDelay(response) ?? policy.delay(for: attempt)
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }

    private nonisolated func retryAfterDelay(_ response: HTTPURLResponse?) -> TimeInterval? {
        guard let value = response?.value(forHTTPHeaderField: "Retry-After") else { return nil }
        if let seconds = TimeInterval(value) { return max(0, min(seconds, 30)) }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        guard let date = formatter.date(from: value) else { return nil }
        return max(0, min(date.timeIntervalSinceNow, 30))
    }
}

nonisolated enum NetworkRetryPolicy: Sendable {
    case none
    case automatic
    case idempotent(maxRetries: Int = 2)
    case custom(maxRetries: Int, retryStatusCodes: Set<Int>, retryURLErrorCodes: Set<URLError.Code>)

    fileprivate func resolved(for request: URLRequest) -> ResolvedNetworkRetryPolicy {
        switch self {
        case .none:
            return ResolvedNetworkRetryPolicy(maxRetries: 0, retryStatusCodes: [], retryURLErrorCodes: [])
        case .automatic:
            let method = request.httpMethod?.uppercased() ?? "GET"
            if ["GET", "HEAD", "OPTIONS"].contains(method) {
                return NetworkRetryPolicy.idempotent().resolved(for: request)
            }
            return NetworkRetryPolicy.none.resolved(for: request)
        case .idempotent(let maxRetries):
            return ResolvedNetworkRetryPolicy(
                maxRetries: maxRetries,
                retryStatusCodes: [408, 429, 500, 502, 503, 504],
                retryURLErrorCodes: [
                    .timedOut,
                    .networkConnectionLost,
                    .cannotFindHost,
                    .cannotConnectToHost,
                    .dnsLookupFailed,
                    .notConnectedToInternet,
                    .internationalRoamingOff,
                    .callIsActive,
                    .dataNotAllowed
                ]
            )
        case .custom(let maxRetries, let retryStatusCodes, let retryURLErrorCodes):
            return ResolvedNetworkRetryPolicy(
                maxRetries: maxRetries,
                retryStatusCodes: retryStatusCodes,
                retryURLErrorCodes: retryURLErrorCodes
            )
        }
    }
}

nonisolated struct ResolvedNetworkRetryPolicy: Sendable {
    let maxRetries: Int
    let retryStatusCodes: Set<Int>
    let retryURLErrorCodes: Set<URLError.Code>

    func shouldRetry(statusCode: Int) -> Bool {
        retryStatusCodes.contains(statusCode)
    }

    func shouldRetry(error: Error) -> Bool {
        if let networkError = error as? NetworkError,
           case .connectionFailed(let underlying) = networkError {
            return shouldRetry(error: underlying)
        }

        guard let urlError = error as? URLError else { return false }
        return retryURLErrorCodes.contains(urlError.code)
    }

    func delay(for attempt: Int) -> TimeInterval {
        let base = min(0.5 * pow(2, Double(attempt)), 8)
        let jitter = Double.random(in: 0...0.25)
        return base + jitter
    }
}

nonisolated enum NetworkError: LocalizedError {
    case invalidResponse
    case offline
    case connectionFailed(Error)
    case httpError(Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "伺服器回應無效"
        case .offline: return "目前沒有網路連線"
        case .connectionFailed(let error): return "連線失敗: \(error.localizedDescription)"
        case .httpError(let code): return "HTTP 錯誤: \(code)"
        }
    }
}
