//
//  TripStopListModelTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
import CoreLocation
import Foundation
import OBAKitCore
@testable import OBAKit

@Suite(.serialized)
struct TripStopListModelTests {

    private struct StopTimeStub: TripStopListEntry {
        let stopID: StopID
        let stopName: String
        let scheduledArrival: Date?
        var stopCoordinate: CLLocationCoordinate2D?
    }

    /// A plain A→E line. Times are only there to be carried through; nothing in
    /// the model reads them.
    private func line(_ ids: [StopID]) -> [StopTimeStub] {
        ids.enumerated().map { index, id in
            StopTimeStub(stopID: id, stopName: "Stop \(id)", scheduledArrival: Date(timeIntervalSince1970: Double(index) * 60))
        }
    }

    private func make(
        _ stops: [StopTimeStub],
        userStopID: StopID? = nil,
        userStopSequence: Int? = nil,
        closestStopID: StopID? = nil
    ) -> TripStopListModel {
        TripStopListModel.make(
            stopTimes: stops,
            userStopID: userStopID,
            userStopSequence: userStopSequence,
            closestStopID: closestStopID
        )
    }

    // MARK: - Shape of the list

    @Test func `Every stop on the trip gets a row, in order`() {
        let model = make(line(["A", "B", "C", "D"]))

        #expect(model.rows.count == 4)
        #expect(model.rows.map(\.name) == ["Stop A", "Stop B", "Stop C", "Stop D"])
    }

    @Test func `A trip with no stop times produces no rows`() {
        let model = make([])

        #expect(model.rows.isEmpty)
        #expect(model.vehicleIndex == nil)
    }

    /// A loop route calls at the same stop twice, and `ForEach` collapses rows
    /// that share an id — so the id has to carry position, not just the stop.
    @Test func `A stop visited twice gets two distinct row ids`() {
        let model = make(line(["A", "B", "A"]))

        #expect(Set(model.rows.map(\.id)).count == 3)
    }

    /// Tapping a row navigates to that stop, so the row has to carry the stop's
    /// own ID — not just the position-qualified `id`, which exists for `ForEach`
    /// and would have to be reverse-parsed to get the stop back out.
    @Test func `Each row carries the stop it stands for`() {
        let model = make(line(["A", "B", "A"]))

        #expect(model.rows.map(\.stopID) == ["A", "B", "A"])
    }

    @Test func `The last stop is the terminal, and only the last`() {
        let model = make(line(["A", "B", "C"]))

        #expect(model.rows.map(\.isTerminal) == [false, false, true])
    }

    // MARK: - The vehicle

    @Test func `Stops behind the vehicle are passed, and the vehicle's own stop is not`() {
        let model = make(line(["A", "B", "C", "D"]), closestStopID: "C")

        #expect(model.vehicleIndex == 2)
        #expect(model.rows.map(\.isPassed) == [true, true, false, false])
        #expect(model.rows.map(\.isVehicleHere) == [false, false, true, false])
    }

    @Test func `A trip with no live vehicle has nothing passed`() {
        let model = make(line(["A", "B", "C"]))

        #expect(model.vehicleIndex == nil)
        #expect(model.rows.allSatisfy { !$0.isPassed })
        #expect(model.rows.allSatisfy { !$0.isVehicleHere })
    }

    /// The vehicle's closest stop is reported by ID alone, so on a loop route it
    /// matches more than one row. Anchored to the rider's stop, the occurrence
    /// that matters is the last one at or before it — the leg being ridden now.
    @Test func `On a loop, the vehicle resolves to the visit before the rider's stop`() {
        let model = make(line(["A", "B", "A", "C"]), userStopID: "C", closestStopID: "A")

        #expect(model.vehicleIndex == 2)
    }

    @Test func `Without a rider's stop, the vehicle resolves to its first visit`() {
        let model = make(line(["A", "B", "A", "C"]), closestStopID: "A")

        #expect(model.vehicleIndex == 0)
    }

    @Test func `A closest stop that isn't on this trip leaves the vehicle unplaced`() {
        let model = make(line(["A", "B", "C"]), closestStopID: "Z")

        #expect(model.vehicleIndex == nil)
        #expect(model.rows.allSatisfy { !$0.isPassed })
    }

    // MARK: - The rider's stop

    @Test func `The rider's stop is marked`() {
        let model = make(line(["A", "B", "C"]), userStopID: "B")

        #expect(model.rows.map(\.isUserStop) == [false, true, false])
    }

    /// `stopSequence` indexes the trip's stop times, so it picks the right visit
    /// where the stop ID alone is ambiguous.
    @Test func `A stop sequence picks the right visit on a loop`() {
        let model = make(line(["A", "B", "A"]), userStopID: "A", userStopSequence: 2)

        #expect(model.rows.map(\.isUserStop) == [false, false, true])
    }

    @Test func `A stop sequence that doesn't match falls back to the stop ID`() {
        let model = make(line(["A", "B", "C"]), userStopID: "C", userStopSequence: 99)

        #expect(model.rows.map(\.isUserStop) == [false, false, true])
    }

    /// Reached from vehicle search there is no originating stop at all.
    @Test func `A trip with no rider's stop marks none`() {
        let model = make(line(["A", "B", "C"]))

        #expect(model.rows.allSatisfy { !$0.isUserStop })
    }

    @Test func `The rider's stop and the terminal can be the same row`() {
        let model = make(line(["A", "B"]), userStopID: "B")

        let last = model.rows[1]
        #expect(last.isUserStop)
        #expect(last.isTerminal)
    }
}
