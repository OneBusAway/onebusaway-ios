//
//  RealtimeVehicleTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import SwiftProtobuf
import Testing
@testable import OBAKitCore

@Suite(.serialized)
final class RealtimeVehicleTests {

    // MARK: - Test Helpers

    private func makeEntity(
        id: String = "vehicle_42",
        latitude: Float = 47.6062,
        longitude: Float = -122.3321,
        bearing: Float? = 180.0,
        tripID: String? = "trip_100",
        routeID: String? = "route_1",
        vehicleID: String? = "bus_101",
        label: String? = "101",
        timestamp: UInt64? = 1_700_000_000
    ) -> TransitRealtime_FeedEntity {
        var entity = TransitRealtime_FeedEntity()
        entity.id = id

        var vehicle = TransitRealtime_VehiclePosition()
        var position = TransitRealtime_Position()
        position.latitude = latitude
        position.longitude = longitude
        if let bearing {
            position.bearing = bearing
        }
        vehicle.position = position

        if let tripID {
            var trip = TransitRealtime_TripDescriptor()
            trip.tripID = tripID
            if let routeID {
                trip.routeID = routeID
            }
            vehicle.trip = trip
        }

        if vehicleID != nil || label != nil {
            var desc = TransitRealtime_VehicleDescriptor()
            if let vehicleID {
                desc.id = vehicleID
            }
            if let label {
                desc.label = label
            }
            vehicle.vehicle = desc
        }

        if let timestamp {
            vehicle.timestamp = timestamp
        }

        entity.vehicle = vehicle
        return entity
    }

    // MARK: - Coordinate Validation Bounds

    @Test func `Valid coordinates within bounds are accepted`() {
        // Standard coordinates
        #expect(RealtimeVehicle.isValidCoordinate(latitude: 47.6062, longitude: -122.3321))
        #expect(RealtimeVehicle.isValidCoordinate(latitude: -33.8688, longitude: 151.2093))

        // Exact boundary coordinates
        #expect(RealtimeVehicle.isValidCoordinate(latitude: 90.0, longitude: 180.0))
        #expect(RealtimeVehicle.isValidCoordinate(latitude: -90.0, longitude: -180.0))
        #expect(RealtimeVehicle.isValidCoordinate(latitude: 90.0, longitude: -180.0))
        #expect(RealtimeVehicle.isValidCoordinate(latitude: -90.0, longitude: 180.0))

        // Non-zero equator and prime meridian
        #expect(RealtimeVehicle.isValidCoordinate(latitude: 0.0, longitude: 45.0))
        #expect(RealtimeVehicle.isValidCoordinate(latitude: 0.0, longitude: -45.0))
        #expect(RealtimeVehicle.isValidCoordinate(latitude: 45.0, longitude: 0.0))
        #expect(RealtimeVehicle.isValidCoordinate(latitude: -45.0, longitude: 0.0))

        // CLLocationCoordinate2D overload
        let validCoord = CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)
        #expect(RealtimeVehicle.isValidCoordinate(validCoord))
    }

    @Test func `Null island (0,0) coordinate is rejected`() {
        #expect(!RealtimeVehicle.isValidCoordinate(latitude: 0.0, longitude: 0.0))
        #expect(!RealtimeVehicle.isValidCoordinate(latitude: -0.0, longitude: 0.0))
        #expect(!RealtimeVehicle.isValidCoordinate(latitude: 0.0, longitude: -0.0))
        #expect(!RealtimeVehicle.isValidCoordinate(latitude: -0.0, longitude: -0.0))

        let nullIsland = CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0)
        #expect(!RealtimeVehicle.isValidCoordinate(nullIsland))
    }

    @Test func `Out-of-bounds coordinates are rejected`() {
        // Latitude > 90
        #expect(!RealtimeVehicle.isValidCoordinate(latitude: 90.0001, longitude: 0.0))
        #expect(!RealtimeVehicle.isValidCoordinate(latitude: 100.0, longitude: -122.0))

        // Latitude < -90
        #expect(!RealtimeVehicle.isValidCoordinate(latitude: -90.0001, longitude: 0.0))
        #expect(!RealtimeVehicle.isValidCoordinate(latitude: -100.0, longitude: -122.0))

        // Longitude > 180
        #expect(!RealtimeVehicle.isValidCoordinate(latitude: 0.0, longitude: 180.0001))
        #expect(!RealtimeVehicle.isValidCoordinate(latitude: 47.0, longitude: 185.0))

        // Longitude < -180
        #expect(!RealtimeVehicle.isValidCoordinate(latitude: 0.0, longitude: -180.0001))
        #expect(!RealtimeVehicle.isValidCoordinate(latitude: 47.0, longitude: -185.0))

        // Non-finite coordinates
        #expect(!RealtimeVehicle.isValidCoordinate(latitude: .nan, longitude: 0.0))
        #expect(!RealtimeVehicle.isValidCoordinate(latitude: 0.0, longitude: .nan))
        #expect(!RealtimeVehicle.isValidCoordinate(latitude: .infinity, longitude: 0.0))
        #expect(!RealtimeVehicle.isValidCoordinate(latitude: 0.0, longitude: -.infinity))
    }

    // MARK: - Initializer & Filtering

    @Test func `Init from entity with valid coordinate succeeds`() {
        let entity = makeEntity(
            id: "bus_1",
            latitude: 47.6062,
            longitude: -122.3321,
            bearing: 90.0,
            tripID: "trip_1",
            routeID: "route_1",
            vehicleID: "veh_1",
            label: "Bus 1"
        )

        guard let vehicle = RealtimeVehicle(from: entity, agency: nil) else {
            Issue.record("Expected vehicle to initialize")
            return
        }
        #expect(vehicle.id == "bus_1")
        #expect(abs(vehicle.coordinate.latitude - 47.6062) < 0.001)
        #expect(abs(vehicle.coordinate.longitude - (-122.3321)) < 0.001)
        #expect(vehicle.bearing == 90.0)
        #expect(vehicle.tripID == "trip_1")
        #expect(vehicle.routeID == "route_1")
        #expect(vehicle.vehicleID == "veh_1")
        #expect(vehicle.vehicleLabel == "Bus 1")
        #expect(vehicle.agencyID == "unknown")
        #expect(vehicle.agencyName == "Unknown Agency")
    }

    @Test func `Init from entity with Null Island coordinate returns nil`() {
        let entity = makeEntity(latitude: 0.0, longitude: 0.0)
        let vehicle = RealtimeVehicle(from: entity, agency: nil)
        #expect(vehicle == nil)
    }

    @Test func `Init from entity with out-of-bounds coordinate returns nil`() {
        let invalidLat = makeEntity(latitude: 91.0, longitude: -122.0)
        #expect(RealtimeVehicle(from: invalidLat, agency: nil) == nil)

        let invalidLon = makeEntity(latitude: 47.0, longitude: 181.0)
        #expect(RealtimeVehicle(from: invalidLon, agency: nil) == nil)
    }

    @Test func `Init from entity without vehicle or position returns nil`() {
        var entityWithoutVehicle = TransitRealtime_FeedEntity()
        entityWithoutVehicle.id = "no_vehicle"
        #expect(RealtimeVehicle(from: entityWithoutVehicle, agency: nil) == nil)

        var entityWithoutPosition = TransitRealtime_FeedEntity()
        entityWithoutPosition.id = "no_position"
        entityWithoutPosition.vehicle = TransitRealtime_VehiclePosition()
        #expect(RealtimeVehicle(from: entityWithoutPosition, agency: nil) == nil)
    }

    @Test func `Memberwise init validates coordinates`() {
        let validCoord = CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)
        let valid = RealtimeVehicle(id: "v1", coordinate: validCoord, bearing: 45.0)
        #expect(valid != nil)

        let nullCoord = CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0)
        let nullVehicle = RealtimeVehicle(id: "v2", coordinate: nullCoord)
        #expect(nullVehicle == nil)

        let outOfBoundsCoord = CLLocationCoordinate2D(latitude: 95.0, longitude: 0.0)
        let oobVehicle = RealtimeVehicle(id: "v3", coordinate: outOfBoundsCoord)
        #expect(oobVehicle == nil)
    }

    // MARK: - Bearing Normalisation

    @Test func `Bearing normalisation maps values to [0, 360)`() {
        // Zero stays zero
        #expect(RealtimeVehicle.normalizeBearing(0.0 as Float) == 0.0)
        #expect(RealtimeVehicle.normalizeBearing(-0.0 as Float) == 0.0)

        // In-range values unchanged
        #expect(RealtimeVehicle.normalizeBearing(45.0 as Float) == 45.0)
        #expect(RealtimeVehicle.normalizeBearing(180.0 as Float) == 180.0)
        #expect(abs(RealtimeVehicle.normalizeBearing(359.9 as Float) - 359.9) < 0.001)

        // Exact 360 wraps to 0
        #expect(RealtimeVehicle.normalizeBearing(360.0 as Float) == 0.0)
        #expect(RealtimeVehicle.normalizeBearing(720.0 as Float) == 0.0)

        // Multiples and overflows
        #expect(RealtimeVehicle.normalizeBearing(405.0 as Float) == 45.0)
        #expect(RealtimeVehicle.normalizeBearing(725.0 as Float) == 5.0)

        // Negative values normalised to positive range
        #expect(RealtimeVehicle.normalizeBearing(-45.0 as Float) == 315.0)
        #expect(RealtimeVehicle.normalizeBearing(-90.0 as Float) == 270.0)
        #expect(RealtimeVehicle.normalizeBearing(-180.0 as Float) == 180.0)
        #expect(RealtimeVehicle.normalizeBearing(-360.0 as Float) == 0.0)
        #expect(RealtimeVehicle.normalizeBearing(-365.0 as Float) == 355.0)
        #expect(RealtimeVehicle.normalizeBearing(-725.0 as Float) == 355.0)

        // Non-finite values
        #expect(RealtimeVehicle.normalizeBearing(Float.nan) == 0.0)
        #expect(RealtimeVehicle.normalizeBearing(Float.infinity) == 0.0)

        // Double overload
        #expect(RealtimeVehicle.normalizeBearing(405.0 as Double) == 45.0)
        #expect(RealtimeVehicle.normalizeBearing(-90.0 as Double) == 270.0)
    }

    @Test func `Bearing description formats compass directions accurately`() {
        let coord = CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)

        let vehicleN = RealtimeVehicle(id: "vN", coordinate: coord, bearing: 0.0)
        #expect(vehicleN?.bearingDescription == "N (0°)")

        let vehicleNE = RealtimeVehicle(id: "vNE", coordinate: coord, bearing: 45.0)
        #expect(vehicleNE?.bearingDescription == "NE (45°)")

        let vehicleE = RealtimeVehicle(id: "vE", coordinate: coord, bearing: 90.0)
        #expect(vehicleE?.bearingDescription == "E (90°)")

        let vehicleSE = RealtimeVehicle(id: "vSE", coordinate: coord, bearing: 135.0)
        #expect(vehicleSE?.bearingDescription == "SE (135°)")

        let vehicleS = RealtimeVehicle(id: "vS", coordinate: coord, bearing: 180.0)
        #expect(vehicleS?.bearingDescription == "S (180°)")

        let vehicleSW = RealtimeVehicle(id: "vSW", coordinate: coord, bearing: 225.0)
        #expect(vehicleSW?.bearingDescription == "SW (225°)")

        let vehicleW = RealtimeVehicle(id: "vW", coordinate: coord, bearing: 270.0)
        #expect(vehicleW?.bearingDescription == "W (270°)")

        let vehicleNW = RealtimeVehicle(id: "vNW", coordinate: coord, bearing: 315.0)
        #expect(vehicleNW?.bearingDescription == "NW (315°)")

        let vehicleNoBearing = RealtimeVehicle(id: "vNone", coordinate: coord, bearing: nil)
        #expect(vehicleNoBearing?.bearingDescription == nil)

        // Negative bearing wraps and formats correctly
        let vehicleNeg = RealtimeVehicle(id: "vNeg", coordinate: coord, bearing: -90.0)
        #expect(vehicleNeg?.bearingDescription == "W (270°)")
    }

    // MARK: - Portability & Concurrency

    @Test func `RealtimeVehicle conforms to Identifiable, Hashable, and Sendable`() async {
        let coord = CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)
        guard let vehicle1 = RealtimeVehicle(id: "v1", coordinate: coord, bearing: 10.0),
              let vehicle2 = RealtimeVehicle(id: "v1", coordinate: coord, bearing: 20.0),
              let vehicle3 = RealtimeVehicle(id: "v2", coordinate: coord, bearing: 10.0) else {
            Issue.record("Failed to initialize test vehicles")
            return
        }

        // Identifiable & Hashable
        #expect(vehicle1.id == "v1")
        #expect(vehicle1 == vehicle2)
        #expect(vehicle1 != vehicle3)

        var set = Set<RealtimeVehicle>()
        set.insert(vehicle1)
        #expect(set.contains(vehicle2))
        #expect(!set.contains(vehicle3))

        // Sendable across Task boundary (watchOS and iOS portability requirement)
        let transferred = await Task.detached { () -> RealtimeVehicle in
            vehicle1
        }.value

        #expect(transferred.id == vehicle1.id)
    }
}
