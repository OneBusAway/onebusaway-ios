//
//  TripCameraFramingTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import Testing
@testable import OBAKit

@Suite(.serialized)
struct TripCameraFramingTests {

    /// Capitol Hill, Seattle — where the fixtures on this branch live.
    private let vehicle = CLLocationCoordinate2D(latitude: 47.6205, longitude: -122.3120)
    private let rider = CLLocationCoordinate2D(latitude: 47.6260, longitude: -122.3120)

    private func contains(_ rect: MKMapRect, _ coordinate: CLLocationCoordinate2D) -> Bool {
        rect.contains(MKMapPoint(coordinate))
    }

    // MARK: - The framed rect

    @Test func `The framed rect holds both the bus and the rider`() throws {
        let rect = try #require(TripCameraFraming.rect(vehicle: vehicle, userLocation: rider))

        #expect(contains(rect, vehicle))
        #expect(contains(rect, rider))
    }

    @Test func `A trip with no known vehicle position doesn't claim the camera`() {
        // Nothing to center on. The caller falls back to the trip's own shape
        // rather than framing the rider alone, which would say nothing about
        // where the bus is.
        #expect(TripCameraFraming.rect(vehicle: nil, userLocation: rider) == nil)
    }

    @Test func `An unknown rider location frames the bus alone`() throws {
        let rect = try #require(TripCameraFraming.rect(vehicle: vehicle, userLocation: nil))

        #expect(contains(rect, vehicle))
    }

    @Test func `A bus already at the rider's corner still gets a legible span`() throws {
        // The screenshot that prompted this: bus and blue dot a few metres
        // apart. Their bounding rect is nearly degenerate, and fitting it slams
        // the camera to maximum zoom.
        let nearby = CLLocationCoordinate2D(latitude: vehicle.latitude + 0.00005, longitude: vehicle.longitude)
        let rect = try #require(TripCameraFraming.rect(vehicle: vehicle, userLocation: nearby))

        let metres = rect.size.height / MKMapPointsPerMeterAtLatitude(vehicle.latitude)
        // A metre of slack: the expansion is computed against the rect's centre
        // latitude, which is a hair off the vehicle's.
        #expect(metres >= TripCameraFraming.minimumSpan - 1)
    }

    // MARK: - The corridor between them

    @Test func `The path between the bus and the rider is framed too`() throws {
        // The bonus: not just the two endpoints, but the streets the bus takes
        // to reach them.
        let bend = CLLocationCoordinate2D(latitude: 47.6230, longitude: -122.3160)
        let rect = try #require(
            TripCameraFraming.rect(vehicle: vehicle, userLocation: rider, corridor: [vehicle, bend, rider])
        )

        #expect(contains(rect, bend))
        #expect(contains(rect, vehicle))
        #expect(contains(rect, rider))
    }

    @Test func `A corridor that detours across town is dropped`() throws {
        // A loop route can run miles away from both endpoints before coming
        // back. Framing that swallows the two things the rider is actually
        // comparing, so the corridor is a bonus the camera gives up first.
        let detour = CLLocationCoordinate2D(latitude: 47.6205, longitude: -122.4400)
        let rect = try #require(
            TripCameraFraming.rect(vehicle: vehicle, userLocation: rider, corridor: [vehicle, detour, rider])
        )

        #expect(!contains(rect, detour))
        #expect(contains(rect, vehicle))
        #expect(contains(rect, rider))
    }

    @Test func `The corridor runs from the bus to the stop nearest the rider`() {
        let ahead = [
            CLLocationCoordinate2D(latitude: 47.6205, longitude: -122.3120),
            CLLocationCoordinate2D(latitude: 47.6230, longitude: -122.3120),
            CLLocationCoordinate2D(latitude: 47.6260, longitude: -122.3120),
            CLLocationCoordinate2D(latitude: 47.6300, longitude: -122.3120)
        ]

        let corridor = TripCameraFraming.corridor(ahead: ahead, userLocation: rider)

        // Truncated at the rider, not run out to the end of the line: the trip
        // continues past them and framing the rest wastes the map.
        #expect(corridor.count == 3)
        #expect(corridor.last?.latitude == 47.6260)
    }

    @Test func `A rider behind the bus gets no corridor to speak of`() {
        // Every point still ahead is further from them than the bus is, so the
        // nearest is the bus itself.
        let behind = CLLocationCoordinate2D(latitude: 47.6100, longitude: -122.3120)
        let ahead = [
            CLLocationCoordinate2D(latitude: 47.6205, longitude: -122.3120),
            CLLocationCoordinate2D(latitude: 47.6260, longitude: -122.3120)
        ]

        #expect(TripCameraFraming.corridor(ahead: ahead, userLocation: behind).count == 1)
    }

    @Test func `No rider location means no corridor`() {
        let ahead = [vehicle, rider]

        #expect(TripCameraFraming.corridor(ahead: ahead, userLocation: nil).isEmpty)
    }

    // MARK: - Framing a bare list of coordinates

    @Test func `A single coordinate frames to the minimum span, not a point`() throws {
        let rect = try #require(TripCameraFraming.rect(of: [vehicle]))

        #expect(rect.size.width > 0)
        #expect(rect.size.height > 0)
        #expect(contains(rect, vehicle))
    }

    @Test func `Nothing to frame yields nothing`() {
        #expect(TripCameraFraming.rect(of: []) == nil)
    }
}
