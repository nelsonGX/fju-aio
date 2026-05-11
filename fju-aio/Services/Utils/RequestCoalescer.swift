import Foundation

actor RequestCoalescer {
    static let shared = RequestCoalescer()

    private var tasks: [String: Task<Any, Error>] = [:]

    private init() {}

    func run<Value: Sendable>(
        key: String,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        if let task = tasks[key] {
            guard let value = try await task.value as? Value else {
                throw NetworkError.invalidResponse
            }
            return value
        }

        let task = Task<Any, Error> {
            try await operation()
        }
        tasks[key] = task

        defer { tasks[key] = nil }

        guard let value = try await task.value as? Value else {
            throw NetworkError.invalidResponse
        }
        return value
    }
}
