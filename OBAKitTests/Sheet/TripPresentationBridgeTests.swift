//
//  TripPresentationBridgeTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import UIKit
@testable import OBAKitCore
@testable import OBAKit

/// Where the map panel sends a trip from My Trip or a vehicle search: onto the
/// sheet stack as `.tripDetails`, over the map, rather than into a modal that
/// covers it.
@MainActor
@Suite(.serialized)
final class TripPresentationBridgeTests {

    private let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)

    /// Error messages the bridge asked to show, and what it showed them from.
    private var presentedErrors: [(message: String, presenter: UIViewController)] = []

    private func makeBridge() -> MapPanelRootController.TripPresentationBridge {
        MapPanelRootController.TripPresentationBridge(coordinator: coordinator) { [weak self] message, presenter in
            self?.presentedErrors.append((message, presenter))
        }
    }

    /// A vehicle whose trip never resolved, which `TripConvertible(vehicleStatus:)`
    /// refuses. Built from the real fixture's entry decoded without its
    /// references, so `trip` is never filled in.
    private func vehicleNotOnATrip() throws -> VehicleStatus {
        let data = Fixtures.loadData(file: "api_where_vehicle_1_4351.json")
        let envelope = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let entry = try #require((envelope["data"] as? [String: Any])?["entry"] as? [String: Any])
        return try JSONDecoder.RESTDecoder().decode(VehicleStatus.self, from: JSONSerialization.data(withJSONObject: entry))
    }

    /// My Trip's route picker and results sit at full height. Left under a
    /// `.medium` trip sheet they would cover the map it's drawn on, and stay
    /// draggable through it.
    @Test func `A trip from My Trip closes My Trip and opens over home`() throws {
        coordinator.push(.routePicker)
        coordinator.push(.currentTrip(route: try Fixtures.createRoute(id: "route_2")))
        let arrival = try Fixtures.arrivalDeparture(tripID: "trip_42")

        makeBridge().present(arrival)

        #expect(coordinator.routeStack == [.home])
        #expect(coordinator.stackedRoutes.map(\.id) == ["tripDetails-trip_42"])
        guard case .tripDetails(let convertible) = coordinator.stackedRoutes.first else {
            Issue.record("Expected a trip sheet, got \(coordinator.stackedRoutes)")
            return
        }
        #expect(convertible.arrivalDeparture === arrival)
    }

    /// A trip that's already open stays as it is, including whatever the rider
    /// opened over it: unwinding would close the trip only to open it again.
    @Test func `The same trip arriving again leaves the open trip alone`() throws {
        let bridge = makeBridge()
        bridge.present(try Fixtures.arrivalDeparture(tripID: "trip_42"))
        coordinator.push(.stopDetails(stopID: "1_75403"))

        bridge.present(try Fixtures.arrivalDeparture(stopID: "stop_2", tripID: "trip_42"))

        #expect(coordinator.stackedRoutes.map(\.id) == ["tripDetails-trip_42", "stopDetails-1_75403"])
    }

    /// The fixture's vehicle is on `1_47649081`. Reached by a vehicle tap and then
    /// from My Trip, that trip is one sheet.
    @Test func `A vehicle on a trip opens that trip's sheet, and its arrival doesn't open another`() throws {
        let vehicle = try Fixtures.loadRESTAPIPayload(type: VehicleStatus.self, fileName: "api_where_vehicle_1_4351.json")
        let bridge = makeBridge()

        bridge.present(vehicleStatus: vehicle)
        #expect(coordinator.stackedRoutes.map(\.id) == ["tripDetails-1_47649081"])

        bridge.present(try Fixtures.arrivalDeparture(tripID: "1_47649081"))
        #expect(coordinator.stackedRoutes.count == 1)
    }

    /// The rider gets the existing `map_controller.vehicle_not_on_trip_error`
    /// alert, shown from the top of the host's presentation chain, and no empty
    /// sheet opens in its place.
    @Test func `A vehicle not on a trip gets the alert instead of a sheet`() throws {
        let vehicle = try vehicleNotOnATrip()
        #expect(TripConvertible(vehicleStatus: vehicle) == nil)
        let host = UIViewController()
        let bridge = makeBridge()
        bridge.host = host

        bridge.present(vehicleStatus: vehicle)

        #expect(coordinator.stackedRoutes.isEmpty)
        #expect(presentedErrors.count == 1)
        #expect(presentedErrors.first?.presenter === host)
    }
}
