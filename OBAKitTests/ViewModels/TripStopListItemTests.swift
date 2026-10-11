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
            userStopIndex: nil,
            boardingMarkerIndex: nil,
            onSelectAction: nil
        )
        #expect(viewModel.temporalState == .future)
        #expect(viewModel.isCurrentVehicleLocation == false)
    }
}

@MainActor
@Suite(.serialized)
final class TripStopViewModelIdentityTests {

    /// A loop route visits the same stop twice. `NSDiffableDataSource` crashes
    /// if two rows share an item identifier (#538). The SwiftUI trip page already
    /// qualifies ids by index (`TripStopListModel`); the UIKit list did not.
    @Test func `A stop visited twice gets two distinct list ids`() throws {
        let data = Fixtures.loadData(file: "trip_details_1_18196913_no_status.json")
        let response = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<TripDetails>.self, from: data)
        let stopTime = try #require(response.entry.stopTimes.first)

        let first = TripStopViewModel(
            stopTime: stopTime,
            arrivalDeparture: nil,
            stopIndex: 0,
            closestStopIndex: nil,
            userStopIndex: nil,
            boardingMarkerIndex: nil,
            onSelectAction: nil
        )
        let second = TripStopViewModel(
            stopTime: stopTime,
            arrivalDeparture: nil,
            stopIndex: 5,
            closestStopIndex: nil,
            userStopIndex: nil,
            boardingMarkerIndex: nil,
            onSelectAction: nil
        )

        #expect(first.id != second.id)
        #expect(first.stop.id == second.stop.id)
        #expect(first != second)
    }

    /// The whole-trip version of the test above. The fixture is an ordinary
    /// point-to-point trip whose stops are all distinct, so running it as-is
    /// proves nothing: the ids would come out unique under the bare `stop.id`
    /// this replaced. Doubling it out-and-back gives every stop a second visit,
    /// which is the shape a loop route actually has — and which halves the id
    /// count the moment `stopIndex` stops qualifying them.
    @Test func `List ids stay unique when a trip revisits every stop`() throws {
        let data = Fixtures.loadData(file: "trip_details_1_18196913_no_status.json")
        let response = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<TripDetails>.self, from: data)
        let outbound = response.entry.stopTimes
        let loop = outbound + outbound.reversed()

        // Pins the premise rather than trusting it. If the doubling is ever dropped,
        // or a future fixture stops producing repeats, this fails here — instead of
        // the test quietly going back to passing for the wrong reason, which is what
        // it did before.
        #expect(Set(loop.map(\.stopID)).count < loop.count)

        let ids = loop.enumerated().map { index, stopTime in
            TripStopViewModel(
                stopTime: stopTime,
                arrivalDeparture: nil,
                stopIndex: index,
                closestStopIndex: nil,
                userStopIndex: nil,
                boardingMarkerIndex: nil,
                onSelectAction: nil
            ).id
        }

        #expect(Set(ids).count == loop.count)
    }

    /// Bare stop ID alone marks every occurrence on a loop; `stopSequence` picks
    /// the rider's boarding visit (#1346).
    @Test func `User destination uses stop sequence on a loop`() throws {
        let data = Fixtures.loadData(file: "trip_details_1_18196913_no_status.json")
        let response = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<TripDetails>.self, from: data)
        var stopTimes = response.entry.stopTimes
        let repeated = stopTimes[1]
        stopTimes.insert(repeated, at: 4)

        let arrivalDeparture = try Fixtures.arrivalDeparture(
            stopSequence: 4,
            stopID: repeated.stopID
        )
        let userStopIndex = try #require(
            TripStopListModel.riderStops(in: stopTimes, arrivalDeparture: arrivalDeparture, sharedDestinationStopID: nil).userStopIndex
        )
        #expect(userStopIndex == 4)

        let firstVisit = TripStopViewModel(
            stopTime: repeated,
            arrivalDeparture: arrivalDeparture,
            stopIndex: 1,
            closestStopIndex: nil,
            userStopIndex: userStopIndex,
            boardingMarkerIndex: nil,
            onSelectAction: nil
        )
        let secondVisit = TripStopViewModel(
            stopTime: repeated,
            arrivalDeparture: arrivalDeparture,
            stopIndex: 4,
            closestStopIndex: nil,
            userStopIndex: userStopIndex,
            boardingMarkerIndex: nil,
            onSelectAction: nil
        )
        #expect(!firstVisit.isUserDestination)
        #expect(secondVisit.isUserDestination)
    }
}

/// The boarding marker a shared trip gives the stop where the sharer got on,
/// once the rider's-stop marker has moved to their exit (#449).
@MainActor
@Suite(.serialized)
final class TripStopBoardingMarkerTests {

    private func stopTimes() throws -> [TripStopTime] {
        let data = Fixtures.loadData(file: "trip_details_1_18196913_no_status.json")
        return try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<TripDetails>.self, from: data).entry.stopTimes
    }

    private func viewModel(_ stopTimes: [TripStopTime], at stopIndex: Int, userStopIndex: Int?, boardingMarkerIndex: Int?) -> TripStopViewModel {
        TripStopViewModel(
            stopTime: stopTimes[stopIndex],
            arrivalDeparture: nil,
            stopIndex: stopIndex,
            closestStopIndex: nil,
            userStopIndex: userStopIndex,
            boardingMarkerIndex: boardingMarkerIndex,
            onSelectAction: nil
        )
    }

    private func viewModel(_ stopTimes: [TripStopTime], at stopIndex: Int, riderStops: TripStopListModel.RiderStops) -> TripStopViewModel {
        viewModel(stopTimes, at: stopIndex, userStopIndex: riderStops.userStopIndex, boardingMarkerIndex: riderStops.boardingMarkerIndex)
    }

    /// The exit is the rider's stop, the boarding stop is marked as such, and
    /// no row — neither of those nor one in between — is both.
    @Test func `A shared destination gives the boarding row its own marker`() throws {
        let stopTimes = try stopTimes()
        let arrivalDeparture = try Fixtures.arrivalDeparture(stopSequence: 4, stopID: stopTimes[4].stopID)

        let riderStops = TripStopListModel.riderStops(
            in: stopTimes,
            arrivalDeparture: arrivalDeparture,
            sharedDestinationStopID: stopTimes[10].stopID
        )
        let boarding = viewModel(stopTimes, at: 4, riderStops: riderStops)
        let between = viewModel(stopTimes, at: 7, riderStops: riderStops)
        let exit = viewModel(stopTimes, at: 10, riderStops: riderStops)

        #expect(boarding.isBoardingStop)
        #expect(!boarding.isUserDestination)
        #expect(!between.isBoardingStop)
        #expect(!between.isUserDestination)
        #expect(exit.isUserDestination)
        #expect(!exit.isBoardingStop)
    }

    /// A trip that was never shared must look exactly as it did: one marker, on
    /// the boarding stop.
    @Test func `Without a shared destination the boarding row keeps the rider's marker alone`() throws {
        let stopTimes = try stopTimes()
        let arrivalDeparture = try Fixtures.arrivalDeparture(stopSequence: 4, stopID: stopTimes[4].stopID)

        let riderStops = TripStopListModel.riderStops(in: stopTimes, arrivalDeparture: arrivalDeparture, sharedDestinationStopID: nil)
        let boarding = viewModel(stopTimes, at: 4, riderStops: riderStops)

        #expect(boarding.isUserDestination)
        #expect(!boarding.isBoardingStop)
    }

    /// `NSDiffableDataSource` only reconfigures a row whose item changed, so the
    /// flag has to take part in equality or a row that gains the badge on a
    /// refresh is left drawing without it.
    @Test func `Rows that differ only in the boarding marker are not equal`() throws {
        let stopTimes = try stopTimes()
        let plain = viewModel(stopTimes, at: 4, userStopIndex: nil, boardingMarkerIndex: nil)
        let marked = viewModel(stopTimes, at: 4, userStopIndex: nil, boardingMarkerIndex: 4)

        #expect(plain != marked)
    }

    @Test func `The boarding badge announces itself to VoiceOver`() {
        let view = TripSegmentView()
        view.setDestinationStatus(user: false, vehicle: false, boarding: true)

        #expect(view.isAccessibilityElement)
        #expect(view.accessibilityLabel == "Boarding stop")
    }
}

@MainActor
@Suite(.serialized)
final class TripProgressViewModelTests {

    @Test func `Zero total stops returns nil`() {
        let vm = TripProgressViewModel(closestStopIndex: 0, totalStops: 0, userStopIndex: nil, boardingStopIndex: nil, arrivalDepartureMinutes: nil)
        #expect(vm == nil)
    }

    @Test func `First stop displays one-based stop count`() throws {
        let vm = try #require(TripProgressViewModel(closestStopIndex: 0, totalStops: 10, userStopIndex: nil, boardingStopIndex: nil, arrivalDepartureMinutes: nil))
        #expect(vm.stopCountText.contains("1 of 10"))
        #expect(abs(vm.progress - 0.1) < 0.001)
    }

    @Test func `Last stop reaches full progress`() throws {
        let vm = try #require(TripProgressViewModel(closestStopIndex: 9, totalStops: 10, userStopIndex: nil, boardingStopIndex: nil, arrivalDepartureMinutes: nil))
        #expect(vm.stopCountText.contains("10 of 10"))
        #expect(abs(vm.progress - 1.0) < 0.001)
    }

    @Test func `Mid trip progress is proportional`() throws {
        let vm = try #require(TripProgressViewModel(closestStopIndex: 4, totalStops: 10, userStopIndex: nil, boardingStopIndex: nil, arrivalDepartureMinutes: nil))
        #expect(abs(vm.progress - 0.5) < 0.001)
    }

    @Test func `No user stop omits ETA`() throws {
        let vm = try #require(TripProgressViewModel(closestStopIndex: 3, totalStops: 10, userStopIndex: nil, boardingStopIndex: nil, arrivalDepartureMinutes: 8))
        #expect(vm.etaText == nil)
    }

    @Test func `User stop behind vehicle reads passed`() throws {
        let vm = try #require(TripProgressViewModel(closestStopIndex: 5, totalStops: 10, userStopIndex: 3, boardingStopIndex: 3, arrivalDepartureMinutes: nil))
        #expect(vm.etaText?.contains("Passed") == true)
    }

    @Test func `Vehicle at user stop reads arriving now`() throws {
        let vm = try #require(TripProgressViewModel(closestStopIndex: 5, totalStops: 10, userStopIndex: 5, boardingStopIndex: 5, arrivalDepartureMinutes: 0))
        #expect(vm.etaText?.contains("Arriving now") == true)
    }

    @Test func `Positive minutes shows ETA text`() throws {
        let vm = try #require(TripProgressViewModel(closestStopIndex: 3, totalStops: 10, userStopIndex: 7, boardingStopIndex: 7, arrivalDepartureMinutes: 8))
        #expect(vm.etaText?.contains("8") == true)
    }

    @Test func `Positive minutes wins over adjacency`() throws {
        let vm = try #require(TripProgressViewModel(closestStopIndex: 3, totalStops: 10, userStopIndex: 4, boardingStopIndex: 4, arrivalDepartureMinutes: 2))
        #expect(vm.etaText?.contains("2") == true)
    }

    @Test func `Zero minutes at adjacent stop reads arriving now`() throws {
        let vm = try #require(TripProgressViewModel(closestStopIndex: 3, totalStops: 10, userStopIndex: 4, boardingStopIndex: 4, arrivalDepartureMinutes: 0))
        #expect(vm.etaText?.contains("Arriving now") == true)
    }

    @Test func `Nil minutes at adjacent stop reads arriving now`() throws {
        let vm = try #require(TripProgressViewModel(closestStopIndex: 3, totalStops: 10, userStopIndex: 4, boardingStopIndex: 4, arrivalDepartureMinutes: nil))
        #expect(vm.etaText?.contains("Arriving now") == true)
    }

    /// A stale prediction (zero or negative minutes) with the vehicle still several
    /// stops away must not claim "Arriving now" — the ETA is omitted instead.
    @Test func `Zero minutes far from stop omits ETA`() throws {
        let vm = try #require(TripProgressViewModel(closestStopIndex: 3, totalStops: 10, userStopIndex: 7, boardingStopIndex: 7, arrivalDepartureMinutes: 0))
        #expect(vm.etaText == nil)
    }

    @Test func `Negative minutes far from stop omits ETA`() throws {
        let vm = try #require(TripProgressViewModel(closestStopIndex: 3, totalStops: 10, userStopIndex: 7, boardingStopIndex: 7, arrivalDepartureMinutes: -3))
        #expect(vm.etaText == nil)
    }

    @Test func `Nil minutes far from stop omits ETA`() throws {
        let vm = try #require(TripProgressViewModel(closestStopIndex: 3, totalStops: 10, userStopIndex: 7, boardingStopIndex: 7, arrivalDepartureMinutes: nil))
        #expect(vm.etaText == nil)
    }

    // MARK: - Shared destination (#449)

    /// The minutes count down to the boarding stop. With the marker on a shared
    /// link's destination, "~3 min to your stop" would put the boarding stop's
    /// ETA next to a stop half an hour further on.
    @Test func `A shared destination does not borrow the boarding stop's ETA`() throws {
        let vm = try #require(TripProgressViewModel(closestStopIndex: 2, totalStops: 20, userStopIndex: 15, boardingStopIndex: 5, arrivalDepartureMinutes: 3))
        #expect(vm.etaText == nil)
    }

    /// A link whose destination the trip never reaches falls back to the
    /// boarding row, and there the minutes are that row's own.
    @Test func `The boarding stop keeps its ETA when it is the user's stop`() throws {
        let vm = try #require(TripProgressViewModel(closestStopIndex: 2, totalStops: 20, userStopIndex: 5, boardingStopIndex: 5, arrivalDepartureMinutes: 3))
        #expect(vm.etaText?.contains("3") == true)
    }

    /// The same resolution `TripFloatingPanelController.updateProgressView`
    /// makes, on real trip data: a shared link puts the marker and the boarding
    /// stop on different rows, and the header shows no ETA.
    @Test func `A shared trip's progress header shows no ETA`() throws {
        let data = Fixtures.loadData(file: "trip_details_1_18196913_no_status.json")
        let stopTimes = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<TripDetails>.self, from: data).entry.stopTimes
        let arrivalDeparture = try Fixtures.arrivalDeparture(stopSequence: 4, stopID: stopTimes[4].stopID)

        let riderStops = TripStopListModel.riderStops(
            in: stopTimes,
            arrivalDeparture: arrivalDeparture,
            sharedDestinationStopID: stopTimes[10].stopID
        )
        #expect(riderStops.boardingIndex == 4)
        #expect(riderStops.userStopIndex == 10)

        let vm = try #require(TripProgressViewModel(
            closestStopIndex: 2,
            totalStops: stopTimes.count,
            userStopIndex: riderStops.userStopIndex,
            boardingStopIndex: riderStops.boardingIndex,
            arrivalDepartureMinutes: 3
        ))
        #expect(vm.etaText == nil)
    }
}
