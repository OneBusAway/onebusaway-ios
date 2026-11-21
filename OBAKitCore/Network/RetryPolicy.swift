import Foundation

/// Deterministic, cancellable retry policy for transient network failures.
public struct RetryPolicy: Sendable, Equatable {
    public let maxAttempts: Int
    public let initialDelay: TimeInterval
    public let maxDelay: TimeInterval
    public let jitter: Bool

    public init(maxAttempts: Int, initialDelay: TimeInterval, maxDelay: TimeInterval, jitter: Bool = false) {
        precondition(maxAttempts > 0)
        precondition(initialDelay >= 0)
        precondition(maxDelay >= initialDelay)
        self.maxAttempts = maxAttempts
        self.initialDelay = initialDelay
        self.maxDelay = maxDelay
        self.jitter = jitter
    }

    /// No retries. Used by API services that opt out of REST retry behavior.
    public static let disabled = RetryPolicy(maxAttempts: 1, initialDelay: 0, maxDelay: 0, jitter: false)

    /// REST defaults: at most three total requests and a bounded 250/500 ms backoff with decorrelated jitter.
    public static let standard = RetryPolicy(maxAttempts: 3, initialDelay: 0.25, maxDelay: 2, jitter: true)

    /// Parses the HTTP `Retry-After` header value (seconds or RFC 7231 / HTTP-date).
    /// - Parameters:
    ///   - headerValue: The raw `Retry-After` header string.
    ///   - now: The current reference date (defaults to `Date()`).
    /// - Returns: Delay in seconds, or `nil` if unparseable.
    public static func parseRetryAfter(_ headerValue: String, now: Date = Date()) -> TimeInterval? {
        let trimmed = headerValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let seconds = Double(trimmed) {
            return max(0, seconds)
        }

        let dateFormats = [
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "EEEE, dd-MMM-yy HH:mm:ss zzz",
            "EEE MMM d HH:mm:ss yyyy"
        ]

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        for format in dateFormats {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                return max(0, date.timeIntervalSince(now))
            }
        }

        return nil
    }

    /// Whether `error` is transient and another attempt remains.
    public func shouldRetry(_ error: Error, attempt: Int) -> Bool {
        guard attempt < maxAttempts else { return false }
        if case APIError.captivePortal = error {
            return false
        }
        if case APIError.cellularDataRestricted = error {
            return false
        }
        if case APIError.rateLimited = error {
            return false
        }
        if case APIError.requestFailure(let response) = error, response.statusCode == 429 {
            if let retryAfter = response.value(forHTTPHeaderField: "Retry-After"),
               let delay = Self.parseRetryAfter(retryAfter),
               delay <= maxDelay {
                return true
            }
            return false
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && (nsError.code == NSURLErrorDataNotAllowed || nsError.code == NSURLErrorCannotFindHost) {
            return false
        }
        switch ErrorClassifier.category(for: error) {
        case .timeout, .offline, .server:
            return true
        case .decoding, .authentication, .unknown:
            return false
        }
    }

    /// Base deterministic exponential backoff delay before jitter.
    public func baseExponentialDelay(after attempt: Int) -> TimeInterval {
        let exponent = min(max(attempt - 1, 0), 62)
        return min(initialDelay * pow(2, Double(exponent)), maxDelay)
    }

    /// Delay before the next attempt after `attempt` failed. Attempts are 1-based.
    public func delay(
        after attempt: Int,
        error: Error? = nil,
        jitterGenerator: (@Sendable (ClosedRange<Double>) -> Double)? = nil
    ) -> TimeInterval {
        if let error = error,
           case APIError.requestFailure(let response) = error,
           response.statusCode == 429,
           let retryAfter = response.value(forHTTPHeaderField: "Retry-After"),
           let retryAfterDelay = Self.parseRetryAfter(retryAfter) {
            return min(retryAfterDelay, maxDelay)
        }

        let baseDelay = baseExponentialDelay(after: attempt)
        guard jitter else {
            return baseDelay
        }

        let minBound = min(initialDelay, baseDelay)
        let maxBound = min(maxDelay, max(minBound, baseDelay * 1.5))
        let range = minBound...maxBound

        if let generator = jitterGenerator {
            return generator(range)
        }
        return Double.random(in: range)
    }

    /// Executes operation until success, a non-transient failure, or attempt limit.
    /// The injected sleeper and jitter generator make scheduling deterministic in tests.
    public func execute<Value: Sendable>(
        operation: @escaping @Sendable (Int) async throws -> Value,
        sleep: @escaping @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) },
        jitterGenerator: (@Sendable (ClosedRange<Double>) -> Double)? = nil
    ) async throws -> Value {
        for attempt in 1...maxAttempts {
            try Task.checkCancellation()
            do {
                return try await operation(attempt)
            } catch {
                guard shouldRetry(error, attempt: attempt) else { throw error }
                let delaySeconds = delay(after: attempt, error: error, jitterGenerator: jitterGenerator)
                let nanoseconds = UInt64(delaySeconds * 1_000_000_000)
                try await sleep(nanoseconds)
            }
        }
        fatalError("RetryPolicy exhausted without returning or throwing")
    }
}
