//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

struct LiveActivityCountdownTests {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func boundedTimerIntervalCountsDownToDeparture() {
        let departure = now.addingTimeInterval(300)
        let interval = LiveActivityCountdown.boundedTimerInterval(departureDate: departure, now: now)

        #expect(interval.lowerBound == now)
        #expect(interval.upperBound == departure)
    }

    @Test func boundedTimerIntervalClampsPastDepartureToZero() {
        let departure = now.addingTimeInterval(-60)
        let interval = LiveActivityCountdown.boundedTimerInterval(departureDate: departure, now: now)

        #expect(interval.lowerBound == departure)
        #expect(interval.upperBound == departure)
    }
}
