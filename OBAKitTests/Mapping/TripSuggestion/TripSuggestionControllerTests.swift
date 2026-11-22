//
//  TripSuggestionControllerTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// Vehicles to hand back, and a count of what was asked.
@MainActor
private final class FakeTripSuggestionDataSource: TripSuggestionDataSource {
    var vehicles: [TripSuggestionCandidate] = []
    /// The confirming reading for each vehicle, by candidate id. Missing means none.
    var laterSightings: [String: VehicleSighting] = [:]
    private(set) var searchCount = 0

    func nearbyVehicles(around coordinate: CLLocationCoordinate2D) async throws -> [TripSuggestionCandidate] {
        searchCount += 1
        return vehicles
    }

    func currentSighting(of candidate: TripSuggestionCandidate) async throws -> VehicleSighting? {
        laterSightings[candidate.id]
    }
}

@MainActor
@Suite(.serialized)
final class TripSuggestionControllerTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let origin = CLLocationCoordinate2D(latitude: 47.6105, longitude: -122.3393)
    private var clock: Date
    private let defaults: UserDefaults
    private let suiteName = "TripSuggestionControllerTests.\(UUID().uuidString)"
    private let mock: AuthorizableLocationManagerMock
    private let locationService: LocationService
    private let dataSource = FakeTripSuggestionDataSource()
    private var controller: TripSuggestionController!
    private var appIsActive = true
    /// Where the last fix put the rider.
    private var riderCoordinate: CLLocationCoordinate2D

    init() {
        clock = start
        riderCoordinate = origin
        defaults = UserDefaults(suiteName: suiteName)!
        mock = AuthorizableLocationManagerMock(updateLocation: TestData.mockSeattleLocation, updateHeading: OBAMockHeading(heading: 0))
        mock._authorizationStatus = .authorizedWhenInUse
        locationService = LocationService(userDefaults: defaults, locationManager: mock)
        controller = TripSuggestionController(
            locationService: locationService,
            userDefaults: defaults,
            dataSource: { [dataSource] in dataSource },
            now: { [unowned self] in clock },
            sleep: { _ in },
            isAppActive: { [unowned self] in appIsActive }
        )
        controller.setActive(true)
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    // MARK: - Helpers

    /// Sends fixes every 5 s from `from` through `through` seconds after `start`,
    /// the rider heading north at `speed`.
    private func ride(speed: Double = 8, from: TimeInterval, through: TimeInterval) async {
        var offset = from
        while offset <= through {
            clock = start.addingTimeInterval(offset)
            riderCoordinate = TripSuggestionMatcher.coordinate(from: origin, distance: speed * offset, bearing: 0)
            mock.location = CLLocation(
                coordinate: riderCoordinate,
                altitude: 0,
                horizontalAccuracy: 5,
                verticalAccuracy: 5,
                course: 0,
                courseAccuracy: 5,
                speed: speed,
                speedAccuracy: 1,
                timestamp: clock
            )
            await controller.waitForSearch()
            offset += 5
        }
    }

    private func vehicle(id: String, heading: Double = 0, metersAhead: Double = 20, routeType: Route.RouteType = .bus) -> TripSuggestionCandidate {
        TripSuggestionCandidate(
            id: id,
            tripID: "trip_\(id)",
            vehicleID: id,
            routeShortName: "10",
            headsign: "Capitol Hill",
            routeType: routeType,
            agencyName: "Metro Transit",
            routeColor: nil,
            routeTextColor: nil,
            serviceDate: nil,
            sighting: VehicleSighting(
                coordinate: TripSuggestionMatcher.coordinate(from: riderCoordinate, distance: metersAhead, bearing: 0),
                fixTime: clock,
                heading: heading
            ),
            arrivalDeparture: nil
        )
    }

    /// Makes `vehicle` report a position beside the rider on the confirming reading.
    private func keepsUp(_ vehicle: TripSuggestionCandidate) {
        dataSource.laterSightings[vehicle.id] = VehicleSighting(coordinate: riderCoordinate, fixTime: clock, heading: 0)
    }

    // MARK: - Tests

    @Test func `nothing is fetched until the rider moves at bus speed`() async {
        dataSource.vehicles = [vehicle(id: "4521")]
        await ride(speed: 1.5, from: 0, through: 120)
        #expect(dataSource.searchCount == 0)
        #expect(controller.suggestion.isEmpty)
    }

    @Test func `a bus moving with the rider is suggested`() async {
        await ride(from: 0, through: 25)
        let bus = vehicle(id: "4521")
        dataSource.vehicles = [bus]
        keepsUp(bus)

        await ride(from: 30, through: 30)

        #expect(dataSource.searchCount == 1)
        #expect(controller.suggestion.map(\.id) == ["4521"])
    }

    @Test func `a bus heading another way is not suggested`() async {
        await ride(from: 0, through: 25)
        let bus = vehicle(id: "4521", heading: 90)
        dataSource.vehicles = [bus]
        keepsUp(bus)

        await ride(from: 30, through: 30)

        #expect(controller.suggestion.isEmpty)
    }

    @Test func `a bus that isn't still alongside on the second reading is not suggested`() async {
        await ride(from: 0, through: 25)
        dataSource.vehicles = [vehicle(id: "4521")]

        await ride(from: 30, through: 30)

        #expect(controller.suggestion.isEmpty)
    }

    @Test func `two buses moving with the rider are both suggested, closest first`() async {
        await ride(from: 0, through: 25)
        let near = vehicle(id: "near", metersAhead: 10)
        let far = vehicle(id: "far", metersAhead: 120)
        dataSource.vehicles = [far, near]
        keepsUp(near)
        dataSource.laterSightings["far"] = VehicleSighting(
            coordinate: TripSuggestionMatcher.coordinate(from: riderCoordinate, distance: 100, bearing: 0),
            fixTime: clock,
            heading: 0
        )

        await ride(from: 30, through: 30)

        #expect(controller.suggestion.map(\.id) == ["near", "far"])
    }

    @Test func `searches are spaced a minute apart`() async {
        await ride(from: 0, through: 25)
        dataSource.vehicles = []
        await ride(from: 30, through: 85)
        #expect(dataSource.searchCount == 1)
        await ride(from: 90, through: 90)
        #expect(dataSource.searchCount == 2)
    }

    @Test func `a dismissed trip isn't suggested again`() async {
        await ride(from: 0, through: 25)
        let bus = vehicle(id: "4521")
        dataSource.vehicles = [bus]
        keepsUp(bus)
        await ride(from: 30, through: 30)
        #expect(!controller.suggestion.isEmpty)

        controller.dismiss()
        #expect(controller.suggestion.isEmpty)

        keepsUp(bus)
        await ride(from: 35, through: 120)
        #expect(dataSource.searchCount >= 2)
        #expect(controller.suggestion.isEmpty)
    }

    @Test func `an ignored suggestion hides after two minutes`() async {
        await ride(from: 0, through: 25)
        let bus = vehicle(id: "4521")
        dataSource.vehicles = [bus]
        keepsUp(bus)
        await ride(from: 30, through: 30)
        #expect(!controller.suggestion.isEmpty)

        await ride(from: 35, through: 145)
        #expect(!controller.suggestion.isEmpty)
        await ride(from: 150, through: 150)
        #expect(controller.suggestion.isEmpty)
    }

    @Test func `stopping for two minutes hides the suggestion`() async {
        await ride(from: 0, through: 25)
        let bus = vehicle(id: "4521")
        dataSource.vehicles = [bus]
        keepsUp(bus)
        await ride(from: 30, through: 30)
        #expect(!controller.suggestion.isEmpty)

        controller.dismiss()
        dataSource.vehicles = []
        await ride(speed: 0, from: 35, through: 150)
        #expect(controller.suggestion.isEmpty)
        let searches = dataSource.searchCount
        // Stopped: no more searching.
        await ride(speed: 0, from: 155, through: 300)
        #expect(dataSource.searchCount == searches)
    }

    @Test func `covering the map hides the suggestion`() async {
        await ride(from: 0, through: 25)
        let bus = vehicle(id: "4521")
        dataSource.vehicles = [bus]
        keepsUp(bus)
        await ride(from: 30, through: 30)
        #expect(!controller.suggestion.isEmpty)

        controller.setActive(false)
        #expect(controller.suggestion.isEmpty)
    }

    @Test func `turning the setting off stops suggestions`() async {
        TripSuggestionSettings.setEnabled(false, userDefaults: defaults)
        dataSource.vehicles = [vehicle(id: "4521")]
        await ride(from: 0, through: 60)
        #expect(dataSource.searchCount == 0)
    }

    @Test func `nothing is fetched while the map is covered`() async {
        controller.setActive(false)
        dataSource.vehicles = [vehicle(id: "4521")]
        await ride(from: 0, through: 60)
        #expect(dataSource.searchCount == 0)
    }

    @Test func `nothing is fetched while the app is in the background`() async {
        appIsActive = false
        dataSource.vehicles = [vehicle(id: "4521")]
        await ride(from: 0, through: 60)
        #expect(dataSource.searchCount == 0)

        appIsActive = true
        await ride(from: 65, through: 65)
        #expect(dataSource.searchCount == 1)
    }

    // MARK: - Copy

    @Test func `copy says bus only when every vehicle is a bus`() {
        let bus = vehicle(id: "1")
        let tram = vehicle(id: "2", routeType: .lightRail)
        #expect(TripSuggestionCopy.title(for: [bus]) == "On Route 10?")
        #expect(TripSuggestionCopy.title(for: [tram]) == "On the 10?")
        #expect(TripSuggestionCopy.title(for: [bus, vehicle(id: "3")]) == "On a bus?")
        #expect(TripSuggestionCopy.title(for: [bus, tram]) == "On a vehicle?")
        #expect(TripSuggestionCopy.chooseButton(for: [bus, tram]) == "Choose Vehicle")
        #expect(TripSuggestionCopy.chooseTitle(for: [bus, bus]) == "Choose a Bus")
    }

    @Test func `vehicle numbers drop the agency prefix`() {
        #expect(TripSuggestionCopy.displayVehicleNumber("1_4521") == "4521")
        #expect(TripSuggestionCopy.displayVehicleNumber("4521") == "4521")
        #expect(TripSuggestionCopy.vehicle(vehicle(id: "1_4521")) == "Bus 4521")
    }
}
