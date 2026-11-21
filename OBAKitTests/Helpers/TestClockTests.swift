//
//  TestClockTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

@Suite(.serialized)
struct TestClockTests {

    /// A caller cancelled before it reaches `sleep` must be turned away, not
    /// parked: `onCancel` has no sleeper to remove at that point, so a
    /// registered one would wait for an `advance(by:)` that never comes.
    @Test(.timeLimit(.minutes(1)))
    func `A caller cancelled before sleeping is not parked`() async {
        let clock = TestClock()

        let sleeper = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await clock.sleep(until: clock.now.advanced(by: .seconds(30)), tolerance: nil)
        }
        let result = await sleeper.result

        #expect(throws: CancellationError.self) { try result.get() }
        #expect(clock.sleeperCount == 0)
    }

    // MARK: - Clock Advance & Instant Progression

    @Test func `Advancing clock moves instant forward`() {
        let clock = TestClock()
        let initialInstant = clock.now

        clock.advance(by: .seconds(45))
        #expect(clock.now.duration(to: initialInstant) == .seconds(-45))

        clock.advance(bySeconds: 30)
        #expect(clock.now.duration(to: initialInstant) == .seconds(-75))
    }

    @Test func `Sleepers wake in order as clock advances`() async throws {
        let clock = TestClock()
        let sleeper1Woke = SendableBox(false)
        let sleeper2Woke = SendableBox(false)

        let deadline1 = clock.now.advanced(by: .seconds(10))
        let deadline2 = clock.now.advanced(by: .seconds(20))

        let task1 = Task {
            try await clock.sleep(until: deadline1, tolerance: nil)
            sleeper1Woke.value = true
        }

        let task2 = Task {
            try await clock.sleep(until: deadline2, tolerance: nil)
            sleeper2Woke.value = true
        }

        await clock.waitForSleepers(count: 2)

        clock.advance(by: .seconds(10))
        try await task1.value
        #expect(sleeper1Woke.value)
        #expect(!sleeper2Woke.value)
        #expect(clock.sleeperCount == 1)

        clock.advance(by: .seconds(10))
        try await task2.value
        #expect(sleeper2Woke.value)
        #expect(clock.sleeperCount == 0)
    }

    // MARK: - Deterministic Dates & Live Activity Fixtures

    @Test func `TestData frozen dates and timestamps are deterministic`() {
        #expect(TestData.frozenTimestamp == 1_700_000_000)
        #expect(TestData.frozenDate == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test func `TestData builds Live Activity content state`() throws {
        let content = TestData.buildActivityContentState(departureOffsets: [300, 900])
        try #require(content.arrivals.count == 2)
        #expect(content.arrivals[0].departureTime == TestData.frozenTimestamp + 300)
        #expect(content.arrivals[1].departureTime == TestData.frozenTimestamp + 900)
    }
}
