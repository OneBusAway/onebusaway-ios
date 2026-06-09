//
//  TripStopListItemTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
@testable import OBAKit
@testable import OBAKitCore

// MARK: - TripStopTemporalState.classify

class TripStopTemporalStateTests: XCTestCase {

    // closestStopIndex nil → every stop is .future
    func test_classify_nilClosestStop_returnsFuture() {
        expect(TripStopTemporalState.classify(stopIndex: 0, closestStopIndex: nil)) == .future
        expect(TripStopTemporalState.classify(stopIndex: 5, closestStopIndex: nil)) == .future
    }

    func test_classify_stopBeforeClosest_returnsPast() {
        expect(TripStopTemporalState.classify(stopIndex: 3, closestStopIndex: 5)) == .past
        expect(TripStopTemporalState.classify(stopIndex: 0, closestStopIndex: 1)) == .past
    }

    func test_classify_stopAtClosest_returnsCurrent() {
        expect(TripStopTemporalState.classify(stopIndex: 5, closestStopIndex: 5)) == .current
        expect(TripStopTemporalState.classify(stopIndex: 0, closestStopIndex: 0)) == .current
    }

    func test_classify_stopAfterClosest_returnsFuture() {
        expect(TripStopTemporalState.classify(stopIndex: 6, closestStopIndex: 5)) == .future
        expect(TripStopTemporalState.classify(stopIndex: 9, closestStopIndex: 5)) == .future
    }

    // Boundary: vehicle at the first stop
    func test_classify_vehicleAtFirstStop() {
        expect(TripStopTemporalState.classify(stopIndex: 0, closestStopIndex: 0)) == .current
        expect(TripStopTemporalState.classify(stopIndex: 1, closestStopIndex: 0)) == .future
    }

    // Boundary: vehicle at the last stop
    func test_classify_vehicleAtLastStop() {
        let last = 9
        expect(TripStopTemporalState.classify(stopIndex: last - 1, closestStopIndex: last)) == .past
        expect(TripStopTemporalState.classify(stopIndex: last, closestStopIndex: last)) == .current
    }
}

// MARK: - TripProgressViewModel

class TripProgressViewModelTests: XCTestCase {

    // No stops → nil view model
    func test_init_zeroTotalStops_returnsNil() {
        let vm = TripProgressViewModel(closestStopIndex: 0, totalStops: 0, userStopIndex: nil, arrivalDepartureMinutes: nil)
        expect(vm).to(beNil())
    }

    // Stop 1 of 10: closestStopIndex=0
    func test_stopCount_firstStop() {
        let vm = TripProgressViewModel(closestStopIndex: 0, totalStops: 10, userStopIndex: nil, arrivalDepartureMinutes: nil)
        expect(vm).notTo(beNil())
        expect(vm?.stopCountText).to(contain("1 of 10"))
        expect(vm?.progress).to(beCloseTo(0.1, within: 0.001))
    }

    // Stop 10 of 10: closestStopIndex=9
    func test_stopCount_lastStop() {
        let vm = TripProgressViewModel(closestStopIndex: 9, totalStops: 10, userStopIndex: nil, arrivalDepartureMinutes: nil)
        expect(vm?.progress).to(beCloseTo(1.0, within: 0.001))
    }

    // No user stop → etaText is nil
    func test_eta_noUserStop_isNil() {
        let vm = TripProgressViewModel(closestStopIndex: 3, totalStops: 10, userStopIndex: nil, arrivalDepartureMinutes: 8)
        expect(vm?.etaText).to(beNil())
    }

    // User stop already passed
    func test_eta_userStopPassed() {
        let vm = TripProgressViewModel(closestStopIndex: 5, totalStops: 10, userStopIndex: 3, arrivalDepartureMinutes: nil)
        expect(vm?.etaText).notTo(beNil())
        expect(vm?.etaText).to(contain("Passed"))
    }

    // Vehicle at user's stop
    func test_eta_vehicleAtUserStop() {
        let vm = TripProgressViewModel(closestStopIndex: 5, totalStops: 10, userStopIndex: 5, arrivalDepartureMinutes: 0)
        expect(vm?.etaText).notTo(beNil())
        expect(vm?.etaText).to(contain("Arriving now"))
    }

    // ETA with positive minutes
    func test_eta_withPositiveMinutes() {
        let vm = TripProgressViewModel(closestStopIndex: 3, totalStops: 10, userStopIndex: 7, arrivalDepartureMinutes: 8)
        expect(vm?.etaText).notTo(beNil())
        expect(vm?.etaText).to(contain("8"))
    }

    // minutes <= 0 → "Arriving now" fallback
    func test_eta_zeroMinutes_arrivingNow() {
        let vm = TripProgressViewModel(closestStopIndex: 3, totalStops: 10, userStopIndex: 7, arrivalDepartureMinutes: 0)
        expect(vm?.etaText).to(contain("Arriving now"))
    }

    // No real-time data (nil minutes) but user stop is ahead → "Arriving now" fallback
    func test_eta_nilMinutesWithUserStopAhead_arrivingNow() {
        let vm = TripProgressViewModel(closestStopIndex: 3, totalStops: 10, userStopIndex: 7, arrivalDepartureMinutes: nil)
        expect(vm?.etaText).to(contain("Arriving now"))
    }

    // Negative minutes falls through the same else branch as zero → "Arriving now"
    func test_eta_negativeMinutes_arrivingNow() {
        let vm = TripProgressViewModel(closestStopIndex: 3, totalStops: 10, userStopIndex: 7, arrivalDepartureMinutes: -3)
        expect(vm?.etaText).to(contain("Arriving now"))
    }

    // Progress fraction: Stop 5 of 10 → 0.5
    func test_progress_midTrip() {
        let vm = TripProgressViewModel(closestStopIndex: 4, totalStops: 10, userStopIndex: nil, arrivalDepartureMinutes: nil)
        expect(vm?.progress).to(beCloseTo(0.5, within: 0.001))
    }
}
