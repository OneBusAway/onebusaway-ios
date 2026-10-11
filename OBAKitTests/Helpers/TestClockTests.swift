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
}
