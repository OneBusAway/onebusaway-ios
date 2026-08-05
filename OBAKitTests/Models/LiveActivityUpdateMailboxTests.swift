//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

struct LiveActivityUpdateCoalescerTests {

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

    @Test func seriallyAppliesFirstAndLatestStateWhileApplyIsInFlight() async {
        let gate = ApplyGate()
        let coalescer = LiveActivityUpdateCoalescer { _, state in
            await gate.apply(state)
        }

        await coalescer.schedule(activityID: "a1", state: state(departureOffset: 600))
        await gate.waitForFirstApply()

        await coalescer.schedule(activityID: "a1", state: state(departureOffset: 500))
        await coalescer.schedule(activityID: "a1", state: state(departureOffset: 300))
        await gate.releaseFirstApply()
        await gate.waitForApplyCount(2)

        let result = await gate.result()
        #expect(result.departureOffsets == [600, 300])
        #expect(!result.appliesOverlapped)
    }

    private actor ApplyGate {
        private let reference = Date(timeIntervalSince1970: 1_700_000_000)
        private var departureOffsets: [Int] = []
        private var appliesOverlapped = false
        private var applying = false
        private var firstApplyWaiter: CheckedContinuation<Void, Never>?
        private var releaseFirstApplyWaiter: CheckedContinuation<Void, Never>?
        private var applyCountWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

        func apply(_ state: TripAttributes.ContentState) async {
            appliesOverlapped = appliesOverlapped || applying
            applying = true
            let departureTime = state.arrivals[0].departureTime
            departureOffsets.append(departureTime - Int(reference.timeIntervalSince1970))

            if departureOffsets.count == 1 {
                firstApplyWaiter?.resume()
                firstApplyWaiter = nil
                await withCheckedContinuation { releaseFirstApplyWaiter = $0 }
            }

            applying = false
            resumeApplyCountWaiters()
        }

        func waitForFirstApply() async {
            if !departureOffsets.isEmpty {
                return
            }
            await withCheckedContinuation { firstApplyWaiter = $0 }
        }

        func releaseFirstApply() {
            releaseFirstApplyWaiter?.resume()
            releaseFirstApplyWaiter = nil
        }

        func waitForApplyCount(_ count: Int) async {
            if departureOffsets.count >= count {
                return
            }
            await withCheckedContinuation { applyCountWaiters.append((count, $0)) }
        }

        func result() -> (departureOffsets: [Int], appliesOverlapped: Bool) {
            (departureOffsets, appliesOverlapped)
        }

        private func resumeApplyCountWaiters() {
            let ready = applyCountWaiters.filter { departureOffsets.count >= $0.0 }
            applyCountWaiters.removeAll { departureOffsets.count >= $0.0 }
            ready.forEach { $0.1.resume() }
        }
    }
}
