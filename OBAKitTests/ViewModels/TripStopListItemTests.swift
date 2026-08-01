//
//  TripStopListItemTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

@MainActor
@Suite(.serialized)
final class TripStopTemporalStateTests {

    @Test func `Nil closest stop classifies every stop as future`() {
        #expect(TripStopTemporalState.classify(stopIndex: 0, closestStopIndex: nil) == .future)
        #expect(TripStopTemporalState.classify(stopIndex: 5, closestStopIndex: nil) == .future)
    }

    @Test func `Stop before closest is past`() {
        #expect(TripStopTemporalState.classify(stopIndex: 3, closestStopIndex: 5) == .past)
        #expect(TripStopTemporalState.classify(stopIndex: 0, closestStopIndex: 1) == .past)
    }

    @Test func `Stop at closest is current`() {
        #expect(TripStopTemporalState.classify(stopIndex: 5, closestStopIndex: 5) == .current)
        #expect(TripStopTemporalState.classify(stopIndex: 0, closestStopIndex: 0) == .current)
    }

    @Test func `Stop after closest is future`() {
        #expect(TripStopTemporalState.classify(stopIndex: 6, closestStopIndex: 5) == .future)
        #expect(TripStopTemporalState.classify(stopIndex: 9, closestStopIndex: 5) == .future)
    }

    @Test func `Vehicle at first stop boundary`() {
        #expect(TripStopTemporalState.classify(stopIndex: 0, closestStopIndex: 0) == .current)
        #expect(TripStopTemporalState.classify(stopIndex: 1, closestStopIndex: 0) == .future)
    }

    @Test func `Vehicle at last stop boundary`() {
        let last = 9
        #expect(TripStopTemporalState.classify(stopIndex: last - 1, closestStopIndex: last) == .past)
        #expect(TripStopTemporalState.classify(stopIndex: last, closestStopIndex: last) == .current)
    }

    /// Trip details with `status: null` (no real-time data) must classify every stop
    /// as `.future` and never mark a stop as the vehicle's current location.
    @Test func `Status-less trip details renders all stops as future`() throws {
        let data = Fixtures.loadData(file: "trip_details_1_18196913_no_status.json")
        let response = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<TripDetails>.self, from: data)
        let tripDetails = response.entry

        #expect(tripDetails.status == nil)
        #expect(!tripDetails.stopTimes.isEmpty)

        let firstStopTime = try #require(tripDetails.stopTimes.first)
        let viewModel = TripStopViewModel(
            stopTime: firstStopTime,
            arrivalDeparture: nil,
            stopIndex: 0,
            closestStopIndex: nil,
            onSelectAction: nil
        )
        #expect(viewModel.temporalState == .future)
        #expect(viewModel.isCurrentVehicleLocation == false)
    }
}

@MainActor
@Suite(.serialized)
final class TripProgressViewModelTests {

    @Test func `Zero total stops returns nil`() {
        let vm = TripProgressViewModel(closestStopIndex: 0, totalStops: 0, userStopIndex: nil, arrivalDepartureMinutes: nil)
        #expect(vm == nil)
    }

    @Test func `First stop displays one-based stop count`() throws {
        let vm = try #require(TripProgressViewModel(closestStopIndex: 0, totalStops: 10, userStopIndex: nil, arrivalDepartureMinutes: nil))
        #expect(vm.stopCountText.contains("1 of 10"))
        #expect(abs(vm.progress - 0.1) < 0.001)
    }

    @Test func `Last stop reaches full progress`() throws {
        let vm = try #require(TripProgressViewModel(closestStopIndex: 9, totalStops: 10, userStopIndex: nil, arrivalDepartureMinutes: nil))
        #expect(vm.stopCountText.contains("10 of 10"))
        #expect(abs(vm.progress - 1.0) < 0.001)
    }

    @Test func `Mid trip progress is proportional`() throws {
        let vm = try #require(TripProgressViewModel(closestStopIndex: 4, totalStops: 10, userStopIndex: nil, arrivalDepartureMinutes: nil))
        #expect(abs(vm.progress - 0.5) < 0.001)
    }

    @Test func `No user stop omits ETA`() throws {
        let vm = try #require(TripProgressViewModel(closestStopIndex: 3, totalStops: 10, userStopIndex: nil, arrivalDepartureMinutes: 8))
        #expect(vm.etaText == nil)
    }

    @Test func `User stop behind vehicle reads passed`() throws {
        let vm = try #require(TripProgressViewModel(closestStopIndex: 5, totalStops: 10, userStopIndex: 3, arrivalDepartureMinutes: nil))
        #expect(vm.etaText?.contains("Passed") == true)
    }

    @Test func `Vehicle at user stop reads arriving now`() throws {
        let vm = try #require(TripProgressViewModel(closestStopIndex: 5, totalStops: 10, userStopIndex: 5, arrivalDepartureMinutes: 0))
        #expect(vm.etaText?.contains("Arriving now") == true)
    }

    @Test func `Positive minutes shows ETA text`() throws {
        let vm = try #require(TripProgressViewModel(closestStopIndex: 3, totalStops: 10, userStopIndex: 7, arrivalDepartureMinutes: 8))
        #expect(vm.etaText?.contains("8") == true)
    }

    @Test func `Positive minutes wins over adjacency`() throws {
        let vm = try #require(TripProgressViewModel(closestStopIndex: 3, totalStops: 10, userStopIndex: 4, arrivalDepartureMinutes: 2))
        #expect(vm.etaText?.contains("2") == true)
    }

    @Test func `Zero minutes at adjacent stop reads arriving now`() throws {
        let vm = try #require(TripProgressViewModel(closestStopIndex: 3, totalStops: 10, userStopIndex: 4, arrivalDepartureMinutes: 0))
        #expect(vm.etaText?.contains("Arriving now") == true)
    }

    @Test func `Nil minutes at adjacent stop reads arriving now`() throws {
        let vm = try #require(TripProgressViewModel(closestStopIndex: 3, totalStops: 10, userStopIndex: 4, arrivalDepartureMinutes: nil))
        #expect(vm.etaText?.contains("Arriving now") == true)
    }

    /// A stale prediction (zero or negative minutes) with the vehicle still several
    /// stops away must not claim "Arriving now" — the ETA is omitted instead.
    @Test func `Zero minutes far from stop omits ETA`() throws {
        let vm = try #require(TripProgressViewModel(closestStopIndex: 3, totalStops: 10, userStopIndex: 7, arrivalDepartureMinutes: 0))
        #expect(vm.etaText == nil)
    }

    @Test func `Negative minutes far from stop omits ETA`() throws {
        let vm = try #require(TripProgressViewModel(closestStopIndex: 3, totalStops: 10, userStopIndex: 7, arrivalDepartureMinutes: -3))
        #expect(vm.etaText == nil)
    }

    @Test func `Nil minutes far from stop omits ETA`() throws {
        let vm = try #require(TripProgressViewModel(closestStopIndex: 3, totalStops: 10, userStopIndex: 7, arrivalDepartureMinutes: nil))
        #expect(vm.etaText == nil)
    }
}
