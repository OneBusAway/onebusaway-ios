//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

struct LiveActivityUpdateMailboxTests {

    private func state(departureOffset: Int) -> TripAttributes.ContentState {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let arrival = TripAttributes.ContentState.ArrivalInfo(
            departureTime: Int(now.timeIntervalSince1970) + departureOffset,
            scheduleStatus: .onTime,
            scheduleDeviation: 0,
            isArrival: false
        )
        return TripAttributes.ContentState(arrivals: [arrival])
    }

    @Test func enqueueKeepsOnlyLatestStatePerActivity() {
        var mailbox = LiveActivityUpdateMailbox()
        let older = state(departureOffset: 600)
        let newer = state(departureOffset: 300)

        mailbox.enqueue(activityID: "a1", state: older)
        mailbox.enqueue(activityID: "a1", state: newer)

        #expect(mailbox.pending.count == 1)
        let taken = mailbox.take(activityID: "a1")
        #expect(taken?.arrivals.first?.departureTime == newer.arrivals.first?.departureTime)
        #expect(mailbox.take(activityID: "a1") == nil)
    }

    @Test func differentActivityIDsStayIndependent() {
        var mailbox = LiveActivityUpdateMailbox()
        mailbox.enqueue(activityID: "a1", state: state(departureOffset: 100))
        mailbox.enqueue(activityID: "a2", state: state(departureOffset: 200))

        #expect(mailbox.pending.count == 2)
        #expect(mailbox.take(activityID: "a1")?.arrivals.first?.departureTime != nil)
        #expect(mailbox.pending.count == 1)
    }
}
