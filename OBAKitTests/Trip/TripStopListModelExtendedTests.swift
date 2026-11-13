//
//  TripStopListModelExtendedTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// Extended tests for `TripStopListModel` run collapsing, terminal stop tags,
/// loop routes, and multi-visit stops.
@Suite(.serialized)
struct TripStopListModelExtendedTests {

    private struct StopTimeStub: TripStopListEntry {
        let stopID: StopID
        let stopName: String
        let scheduledArrival: Date?
        var stopCoordinate: CLLocationCoordinate2D?
    }

    private func makeStops(_ ids: [StopID]) -> [StopTimeStub] {
        ids.enumerated().map { index, id in
            StopTimeStub(
                stopID: id,
                stopName: "Stop \(id)",
                scheduledArrival: Date(timeIntervalSince1970: Double(index * 60)),
                stopCoordinate: CLLocationCoordinate2D(latitude: 47.60 + Double(index) * 0.001, longitude: -122.33)
            )
        }
    }

    private func makeModel(
        _ stops: [StopTimeStub],
        userStopID: StopID? = nil,
        userStopSequence: Int? = nil,
        closestStopID: StopID? = nil,
        sharedDestinationStopID: StopID? = nil
    ) -> TripStopListModel {
        TripStopListModel.make(
            stopTimes: stops,
            userStopID: userStopID,
            userStopSequence: userStopSequence,
            closestStopID: closestStopID,
            sharedDestinationStopID: sharedDestinationStopID
        )
    }

    // MARK: - Single Stop and Minimal Models

    @Test func `Single stop trip marks that stop as terminal and not passed without vehicle`() {
        let model = makeModel(makeStops(["A"]))

        #expect(model.rows.count == 1)
        #expect(model.rows[0].isTerminal == true)
        #expect(model.rows[0].isPassed == false)
        #expect(model.vehicleIndex == nil)
    }

    @Test func `Single stop trip with vehicle at stop marks vehicle here`() {
        let model = makeModel(makeStops(["A"]), closestStopID: "A")

        #expect(model.rows.count == 1)
        #expect(model.vehicleIndex == 0)
        #expect(model.rows[0].isVehicleHere == true)
        #expect(model.rows[0].isPassed == false)
    }

    // MARK: - Vehicle at Terminal

    @Test func `Vehicle at last stop marks all previous stops passed and terminal active`() {
        let model = makeModel(makeStops(["A", "B", "C"]), closestStopID: "C")

        #expect(model.vehicleIndex == 2)
        #expect(model.rows[0].isPassed == true)
        #expect(model.rows[1].isPassed == true)
        #expect(model.rows[2].isPassed == false)
        #expect(model.rows[2].isVehicleHere == true)
        #expect(model.rows[2].isTerminal == true)
    }

    // MARK: - User Stop Selection

    @Test func `User stop index correctly resolved by stop ID`() {
        let model = makeModel(makeStops(["A", "B", "C"]), userStopID: "B")

        #expect(model.userIndex == 1)
        #expect(model.rows[1].isUserStop == true)
        #expect(model.rows[0].isUserStop == false)
        #expect(model.rows[2].isUserStop == false)
    }

    @Test func `User stop sequence disambiguates duplicate stop IDs on loop route`() {
        let stops = [
            StopTimeStub(stopID: "A", stopName: "Stop A", scheduledArrival: Date(timeIntervalSince1970: 0)),
            StopTimeStub(stopID: "B", stopName: "Stop B", scheduledArrival: Date(timeIntervalSince1970: 60)),
            StopTimeStub(stopID: "A", stopName: "Stop A Loop", scheduledArrival: Date(timeIntervalSince1970: 120))
        ]

        let modelFirst = makeModel(stops, userStopID: "A", userStopSequence: 0)
        #expect(modelFirst.userIndex == 0)

        let modelSecond = makeModel(stops, userStopID: "A", userStopSequence: 2)
        #expect(modelSecond.userIndex == 2)
    }

    // MARK: - Coordinates and Row Construction

    @Test func `Row preserves coordinates when available`() {
        let stops = makeStops(["A", "B"])
        let model = makeModel(stops)

        #expect(model.rows[0].coordinate != nil)
        #expect(model.rows[1].coordinate != nil)
        #expect(model.rows[0].coordinate?.latitude == 47.60)
    }
}
