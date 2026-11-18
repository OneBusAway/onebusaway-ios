import Foundation
import Testing
@testable import OBAKitCore

@Suite(.serialized)
final class RetryPolicyTests {
    @Test func `Transient failures retry with bounded exponential schedule`() async throws {
        let policy = RetryPolicy(maxAttempts: 3, initialDelay: 0.25, maxDelay: 1)
        let attempts = SendableBox(0)
        let delays = SendableBox<[UInt64]>([])

        let value = try await policy.execute(operation: { _ in
            attempts.value += 1
            if attempts.value < 3 {
                throw URLError(.timedOut)
            }
            return "ok"
        }, sleep: { delays.value.append($0) })

        #expect(value == "ok")
        #expect(attempts.value == 3)
        #expect(delays.value == [250_000_000, 500_000_000])
    }

    @Test func `Non transient failures stop without retry`() async {
        let policy = RetryPolicy(maxAttempts: 5, initialDelay: 1, maxDelay: 8)
        let attempts = SendableBox(0)
        let sleepCalled = SendableBox(false)

        await #expect(throws: URLError.self) {
            try await policy.execute(operation: { _ in
                attempts.value += 1
                throw URLError(.cancelled)
            }, sleep: { _ in sleepCalled.value = true })
        }

        #expect(attempts.value == 1)
        #expect(!sleepCalled.value)
    }

    @Test func `Cancellation stops before next attempt`() async {
        let policy = RetryPolicy(maxAttempts: 3, initialDelay: 1, maxDelay: 1)
        let sleeping = SendableBox(false)

        let task = Task {
            try await policy.execute(operation: { _ in
                throw URLError(.timedOut)
            }, sleep: { _ in
                sleeping.value = true
                try await Task.sleep(for: .seconds(60))
            })
        }

        var yields = 0
        while !sleeping.value {
            yields += 1
            if yields > 10_000 {
                Issue.record("Timed out waiting for task to begin sleeping")
                break
            }
            await Task.yield()
        }

        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func `Cellular data restricted error is not retried`() async {
        let policy = RetryPolicy(maxAttempts: 3, initialDelay: 0.25, maxDelay: 1)
        let attempts = SendableBox(0)
        let sleepCalled = SendableBox(false)

        await #expect(throws: Error.self) {
            try await policy.execute(operation: { _ in
                attempts.value += 1
                throw URLError(.dataNotAllowed)
            }, sleep: { _ in sleepCalled.value = true })
        }

        #expect(attempts.value == 1)
        #expect(!sleepCalled.value)
    }

    @Test func `Captive portal error is not retried`() async {
        let policy = RetryPolicy(maxAttempts: 3, initialDelay: 0.25, maxDelay: 1)
        let attempts = SendableBox(0)
        let sleepCalled = SendableBox(false)

        await #expect(throws: APIError.self) {
            try await policy.execute(operation: { _ in
                attempts.value += 1
                throw APIError.captivePortal
            }, sleep: { _ in sleepCalled.value = true })
        }

        #expect(attempts.value == 1)
        #expect(!sleepCalled.value)
    }

    @Test func `Rate limited error is not retried`() async {
        let policy = RetryPolicy(maxAttempts: 3, initialDelay: 0.25, maxDelay: 1)
        let attempts = SendableBox(0)
        let sleepCalled = SendableBox(false)

        await #expect(throws: APIError.self) {
            try await policy.execute(operation: { _ in
                attempts.value += 1
                throw APIError.rateLimited
            }, sleep: { _ in sleepCalled.value = true })
        }

        #expect(attempts.value == 1)
        #expect(!sleepCalled.value)
    }

    @Test func `Rate limited request failure is not retried`() async {
        let policy = RetryPolicy(maxAttempts: 3, initialDelay: 0.25, maxDelay: 1)
        let attempts = SendableBox(0)
        let sleepCalled = SendableBox(false)
        let response = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 429, httpVersion: nil, headerFields: nil)!

        await #expect(throws: APIError.self) {
            try await policy.execute(operation: { _ in
                attempts.value += 1
                throw APIError.requestFailure(response)
            }, sleep: { _ in sleepCalled.value = true })
        }

        #expect(attempts.value == 1)
        #expect(!sleepCalled.value)
    }

    @Test func `Cannot find host error is not retried`() async {
        let policy = RetryPolicy(maxAttempts: 3, initialDelay: 0.25, maxDelay: 1)
        let attempts = SendableBox(0)
        let sleepCalled = SendableBox(false)

        await #expect(throws: Error.self) {
            try await policy.execute(operation: { _ in
                attempts.value += 1
                throw URLError(.cannotFindHost)
            }, sleep: { _ in sleepCalled.value = true })
        }

        #expect(attempts.value == 1)
        #expect(!sleepCalled.value)
    }

    @Test func `Exhausted retries throw final attempt error`() async {
        let policy = RetryPolicy(maxAttempts: 3, initialDelay: 0.1, maxDelay: 0.4)
        let attempts = SendableBox(0)
        let delays = SendableBox<[UInt64]>([])

        await #expect(throws: URLError.self) {
            try await policy.execute(operation: { attempt in
                attempts.value += 1
                throw URLError(.timedOut)
            }, sleep: { delays.value.append($0) })
        }

        #expect(attempts.value == 3)
        #expect(delays.value.count == 2)
        #expect(delays.value == [100_000_000, 200_000_000])
    }

    @Test func `Delay calculation respects initialDelay exponentiation and maxDelay ceiling`() {
        let policy = RetryPolicy(maxAttempts: 6, initialDelay: 0.25, maxDelay: 1.5)

        #expect(policy.delay(after: 0) == 0.25)
        #expect(policy.delay(after: 1) == 0.25)
        #expect(policy.delay(after: 2) == 0.50)
        #expect(policy.delay(after: 3) == 1.00)
        #expect(policy.delay(after: 4) == 1.50)
        #expect(policy.delay(after: 5) == 1.50)
        #expect(policy.delay(after: 100) == 1.50)
    }

    @Test func `Server and HTTP 5xx errors trigger retry while 4xx errors stop immediately`() {
        let policy = RetryPolicy(maxAttempts: 3, initialDelay: 0.25, maxDelay: 1.0)

        let server500 = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 500, httpVersion: nil, headerFields: nil)!
        let client404 = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 404, httpVersion: nil, headerFields: nil)!
        let client401 = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 401, httpVersion: nil, headerFields: nil)!

        #expect(policy.shouldRetry(APIError.requestFailure(server500), attempt: 1) == true)
        #expect(policy.shouldRetry(APIError.serverError, attempt: 1) == true)
        #expect(policy.shouldRetry(APIError.requestNotFound(client404), attempt: 1) == false)
        #expect(policy.shouldRetry(APIError.requestFailure(client401), attempt: 1) == false)
        #expect(policy.shouldRetry(APIError.serverError, attempt: 3) == false)
    }
}
