import Foundation

/// Deterministic, cancellable retry policy for transient network failures.
public struct RetryPolicy: Sendable, Equatable {
    public let maxAttempts: Int
    public let initialDelay: TimeInterval
    public let maxDelay: TimeInterval

    public init(maxAttempts: Int, initialDelay: TimeInterval, maxDelay: TimeInterval) {
        precondition(maxAttempts > 0)
        precondition(initialDelay >= 0)
        precondition(maxDelay >= initialDelay)
        self.maxAttempts = maxAttempts
        self.initialDelay = initialDelay
        self.maxDelay = maxDelay
    }

    /// No retries. Used by API services that opt out of REST retry behavior.
    public static let disabled = RetryPolicy(maxAttempts: 1, initialDelay: 0, maxDelay: 0)

    /// REST defaults: at most three total requests and a bounded 250/500 ms backoff.
    public static let standard = RetryPolicy(maxAttempts: 3, initialDelay: 0.25, maxDelay: 2)

    /// Whether `error` is transient and another attempt remains.
    public func shouldRetry(_ error: Error, attempt: Int) -> Bool {
        guard attempt < maxAttempts else { return false }
        if case APIError.captivePortal = error {
            return false
        }
        switch ErrorClassifier.category(for: error) {
        case .timeout, .offline, .server:
            return true
        case .decoding, .authentication, .unknown:
            return false
        }
    }

    /// Delay before the next attempt after `attempt` failed. Attempts are 1-based.
    public func delay(after attempt: Int) -> TimeInterval {
        let exponent = min(max(attempt - 1, 0), 62)
        return min(initialDelay * pow(2, Double(exponent)), maxDelay)
    }

    /// Executes operation until success, a non-transient failure, or attempt limit.
    /// The injected sleeper makes scheduling deterministic in tests.
    public func execute<Value: Sendable>(
        operation: @escaping @Sendable (Int) async throws -> Value,
        sleep: @escaping @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }
    ) async throws -> Value {
        for attempt in 1...maxAttempts {
            try Task.checkCancellation()
            do {
                return try await operation(attempt)
            } catch {
                guard shouldRetry(error, attempt: attempt) else { throw error }
                let nanoseconds = UInt64(delay(after: attempt) * 1_000_000_000)
                try await sleep(nanoseconds)
            }
        }
        fatalError("RetryPolicy exhausted without returning or throwing")
    }
}
