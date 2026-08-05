//
//  StopRouteFocusModelTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Testing
import UIKit
import OBAKitCore
@testable import OBAKit

private struct StubMapDeparture: MapDepartureEntry {
    let id: String
    let routeID: RouteID
    let arrivalDepartureMinutes: Int
    let routeShortName: String
    let routeColor: UIColor
    let shapeID: String?
    let tripID: String
    let vehicleID: String?
    let vehicleCoordinate: CLLocationCoordinate2D?
    let orientation: CLLocationDirection

    var temporalState: TemporalState {
        arrivalDepartureMinutes < 0 ? .past : (arrivalDepartureMinutes == 0 ? .present : .future)
    }
}

private func dep(
    _ id: String,
    route: String,
    mins: Int,
    shape: String? = "shape_\(#function)",
    trip: String? = nil,
    vehicle: String? = nil,
    located: Bool = true
) -> StubMapDeparture {
    StubMapDeparture(
        id: id,
        routeID: route,
        arrivalDepartureMinutes: mins,
        routeShortName: route,
        routeColor: .systemBlue,
        shapeID: shape,
        tripID: trip ?? "trip_\(id)",
        vehicleID: vehicle,
        vehicleCoordinate: located ? CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3) : nil,
        orientation: 90
    )
}

@MainActor
@Suite(.serialized)
final class StopRouteFocusModelTests {

    // MARK: - Filter parity with the list

    // `visibleDepartures` takes real `ArrivalDeparture`s, which only decode from
    // JSON. `arrivals_and_departures_for_stop_1_10020.json` has 4 arrivals split
    // across two routes (1_30 x2, 1_65 x2), all located, no terminal duplicates —
    // load it once via `Fixtures.loadRESTAPIPayload` and reuse it across the three
    // filter-parity cases the spec calls out.

    private static func fixtureDepartures() throws -> [ArrivalDeparture] {
        let payload = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals_and_departures_for_stop_1_10020.json"
        )
        return payload.arrivalsAndDepartures
    }

    @Test func `isListFiltered true excludes hidden routes`() throws {
        let deps = try Self.fixtureDepartures()
        #expect(deps.map(\.routeID).contains("1_30"))

        let prefs = StopPreferences(sortType: .time, hiddenRoutes: ["1_30"])
        let visible = StopRouteFocusModel.visibleDepartures(deps, isListFiltered: true, preferences: prefs)

        #expect(!visible.map(\.routeID).contains("1_30"))
        #expect(visible.allSatisfy { $0.routeID == "1_65" })
        #expect(visible.count == 2)
    }

    @Test func `isListFiltered false includes hidden routes because the rider toggled filtering off`() throws {
        let deps = try Self.fixtureDepartures()

        let prefs = StopPreferences(sortType: .time, hiddenRoutes: ["1_30"])
        let visible = StopRouteFocusModel.visibleDepartures(deps, isListFiltered: false, preferences: prefs)

        // The list is showing 1_30 too (filter off), so the map must not hide it.
        #expect(visible.map(\.routeID).contains("1_30"))
        #expect(visible.count == deps.count)
    }

    @Test func `Terminal duplicates are collapsed whether or not the list filter is on`() throws {
        let deps = try Self.fixtureDepartures()
        var withDuplicate = deps
        withDuplicate.append(deps[0]) // simulate a terminal arrival/departure pair
        #expect(withDuplicate.count == deps.count + 1)

        let noPrefs = StopPreferences()

        let filteredOn = StopRouteFocusModel.visibleDepartures(withDuplicate, isListFiltered: true, preferences: noPrefs)
        #expect(filteredOn.count == deps.count)

        let filteredOff = StopRouteFocusModel.visibleDepartures(withDuplicate, isListFiltered: false, preferences: noPrefs)
        #expect(filteredOff.count == deps.count)
    }

    // MARK: - Ordering and membership

    @Test func `Input is sorted by minutes, not taken as given`() {
        // filteredDepartures is NOT sorted at its call site — the model must sort.
        let model = StopRouteFocusModel.make(
            departures: [dep("b", route: "62", mins: 9), dep("a", route: "H", mins: 2)],
            routeCap: 6
        )
        #expect(model.routes.map(\.routeID) == ["H", "62"])
    }

    @Test func `Past departures contribute neither route nor vehicle`() {
        let model = StopRouteFocusModel.make(
            departures: [dep("gone", route: "24", mins: -3), dep("soon", route: "H", mins: 4)],
            routeCap: 6
        )
        #expect(model.routes.map(\.routeID) == ["H"])
        #expect(model.vehicles.allSatisfy { $0.routeID == "H" })
    }

    @Test func `Routes dedupe by routeID, keeping soonest-first order`() {
        let model = StopRouteFocusModel.make(
            departures: [dep("h1", route: "H", mins: 1), dep("r62", route: "62", mins: 3), dep("h2", route: "H", mins: 12)],
            routeCap: 6
        )
        #expect(model.routes.map(\.routeID) == ["H", "62"])
    }

    @Test func `Route count is capped by soonest arrival`() {
        let departures = (1...9).map { dep("d\($0)", route: "R\($0)", mins: $0) }
        let model = StopRouteFocusModel.make(departures: departures, routeCap: 6)
        #expect(model.routes.count == 6)
        #expect(model.routes.map(\.routeID) == ["R1", "R2", "R3", "R4", "R5", "R6"])
    }

    // MARK: - Shapes

    @Test func `A route takes its shape from its soonest departure`() {
        let model = StopRouteFocusModel.make(
            departures: [dep("h2", route: "H", mins: 12, shape: "late"), dep("h1", route: "H", mins: 1, shape: "early")],
            routeCap: 6
        )
        #expect(model.routes.first?.shapeID == "early")
    }

    @Test func `A route whose soonest departure has no shape yields no shape`() {
        let model = StopRouteFocusModel.make(
            departures: [dep("h1", route: "H", mins: 1, shape: nil)],
            routeCap: 6
        )
        #expect(model.routes.first?.shapeID == nil)
    }

    // MARK: - Vehicles

    @Test func `Vehicles dedupe by vehicleID`() {
        let model = StopRouteFocusModel.make(
            departures: [dep("a", route: "H", mins: 1, vehicle: "6821"), dep("b", route: "H", mins: 30, vehicle: "6821")],
            routeCap: 6
        )
        #expect(model.vehicles.count == 1)
    }

    @Test func `Vehicles without a vehicleID fall back to tripID for identity`() {
        let model = StopRouteFocusModel.make(
            departures: [dep("a", route: "H", mins: 1, trip: "t1"), dep("b", route: "H", mins: 5, trip: "t2")],
            routeCap: 6
        )
        #expect(model.vehicles.count == 2)
    }

    @Test func `A departure with no coordinate produces no vehicle`() {
        let model = StopRouteFocusModel.make(
            departures: [dep("a", route: "H", mins: 1, located: false)],
            routeCap: 6
        )
        #expect(model.vehicles.isEmpty)
        #expect(model.routes.first?.hasLiveVehicle == false)
    }

    @Test func `hasLiveVehicle is true only for routes with a located vehicle`() {
        let model = StopRouteFocusModel.make(
            departures: [dep("a", route: "H", mins: 1, located: true), dep("b", route: "62", mins: 3, located: false)],
            routeCap: 6
        )
        let byRoute = Dictionary(uniqueKeysWithValues: model.routes.map { ($0.routeID, $0.hasLiveVehicle) })
        #expect(byRoute["H"] == true)
        #expect(byRoute["62"] == false)
    }

    @Test func `Vehicles for routes beyond the cap are dropped`() {
        let departures = (1...9).map { dep("d\($0)", route: "R\($0)", mins: $0) }
        let model = StopRouteFocusModel.make(departures: departures, routeCap: 6)
        #expect(model.vehicles.allSatisfy { model.routes.map(\.routeID).contains($0.routeID) })
    }
}
