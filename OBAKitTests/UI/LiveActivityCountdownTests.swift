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

    @Test func futureDepartureUsesTimerNotNow() {
        let departure = now.addingTimeInterval(300)
        #expect(!LiveActivityCountdown.shouldShowNow(departureDate: departure, now: now))
    }

    @Test func presentDepartureShowsNow() {
        #expect(LiveActivityCountdown.shouldShowNow(departureDate: now, now: now))
    }

    @Test func pastDepartureShowsNow() {
        let departure = now.addingTimeInterval(-60)
        #expect(LiveActivityCountdown.shouldShowNow(departureDate: departure, now: now))
    }
}
