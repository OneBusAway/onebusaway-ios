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
}
