//
//  MapPanelCameraCompensationTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import SwiftUI
import Testing
@testable import OBAKit

/// A sheet settling changes the map's bottom padding; the map should stay where
/// it is unless the app framed something itself.
@MainActor
@Suite(.serialized)
struct MapPanelCameraCompensationTests {
    private let seattle = CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)
    /// Map points per screen point; a street-level zoom.
    private let scale = 2.0

    private func mapPointOffset(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> (dx: Double, dy: Double) {
        let a = MKMapPoint(from), b = MKMapPoint(to)
        return (b.x - a.x, b.y - a.y)
    }

    // MARK: - shiftedCenter

    /// The visible area's centre moves up by half the change, so the new centre is
    /// that far north on a map facing north.
    @Test func `A taller padding moves the centre north by half the change`() {
        let shifted = MapPanelCameraCompensation.shiftedCenter(seattle, paddingDelta: 200, mapPointsPerScreenPoint: scale, heading: 0)
        let offset = mapPointOffset(from: seattle, to: shifted)
        #expect(abs(offset.dx) < 1e-6)
        #expect(abs(offset.dy - -200.0) < 1e-6)
    }

    @Test func `A shorter padding moves the centre south`() {
        let shifted = MapPanelCameraCompensation.shiftedCenter(seattle, paddingDelta: -100, mapPointsPerScreenPoint: scale, heading: 0)
        let offset = mapPointOffset(from: seattle, to: shifted)
        #expect(abs(offset.dy - 100.0) < 1e-6)
    }

    /// Facing east, up the screen is east on the ground.
    @Test func `With the map turned to face east the centre moves east`() {
        let shifted = MapPanelCameraCompensation.shiftedCenter(seattle, paddingDelta: 200, mapPointsPerScreenPoint: scale, heading: 90)
        let offset = mapPointOffset(from: seattle, to: shifted)
        #expect(abs(offset.dx - 200.0) < 1e-6)
        #expect(abs(offset.dy) < 1e-6)
    }

    /// Facing south, up the screen is south, so a taller padding moves the centre south.
    @Test func `With the map turned to face south the centre moves south`() {
        let shifted = MapPanelCameraCompensation.shiftedCenter(seattle, paddingDelta: 200, mapPointsPerScreenPoint: scale, heading: 180)
        let offset = mapPointOffset(from: seattle, to: shifted)
        #expect(abs(offset.dx) < 1e-6)
        #expect(abs(offset.dy - 200.0) < 1e-6)
    }

    /// The same change in points is a longer way on the ground when zoomed out.
    @Test func `The shift scales with the map's zoom`() {
        let near = MapPanelCameraCompensation.shiftedCenter(seattle, paddingDelta: 100, mapPointsPerScreenPoint: 1, heading: 0)
        let far = MapPanelCameraCompensation.shiftedCenter(seattle, paddingDelta: 100, mapPointsPerScreenPoint: 8, heading: 0)
        #expect(abs(mapPointOffset(from: seattle, to: far).dy - 8 * mapPointOffset(from: seattle, to: near).dy) < 1e-6)
    }

    @Test func `No change leaves the centre where it is`() {
        let shifted = MapPanelCameraCompensation.shiftedCenter(seattle, paddingDelta: 0, mapPointsPerScreenPoint: scale, heading: 45)
        #expect(shifted.latitude == seattle.latitude)
        #expect(shifted.longitude == seattle.longitude)
    }

    // MARK: - compensates

    /// Nothing framed since the camera settled: a sheet settling on its own.
    @Test func `A sheet settling on its own keeps the map still`() {
        let framed = MapCameraPosition.region(MKCoordinateRegion(center: seattle, latitudinalMeters: 1000, longitudinalMeters: 1000))
        #expect(MapPanelCameraCompensation.compensates(position: framed, positionAtSettle: framed))
    }

    /// The app framed a stop, a trip or a region since: that fits the new visible area.
    @Test func `A framing since the camera settled is left to MapKit`() {
        let settled = MapCameraPosition.region(MKCoordinateRegion(center: seattle, latitudinalMeters: 1000, longitudinalMeters: 1000))
        let framed = MapCameraPosition.rect(MKMapRect(origin: MKMapPoint(seattle), size: MKMapSize(width: 500, height: 500)))
        #expect(!MapPanelCameraCompensation.compensates(position: framed, positionAtSettle: settled))
    }

    /// Following the rider keeps their dot centred in the visible map.
    @Test func `Following the rider is left to MapKit`() {
        let following = MapCameraPosition.userLocation(fallback: .automatic)
        #expect(!MapPanelCameraCompensation.compensates(position: following, positionAtSettle: following))
    }

    @Test func `Before the camera first settles nothing is compensated`() {
        let framed = MapCameraPosition.region(MKCoordinateRegion(center: seattle, latitudinalMeters: 1000, longitudinalMeters: 1000))
        #expect(!MapPanelCameraCompensation.compensates(position: framed, positionAtSettle: nil))
    }

    // MARK: - compensatedPosition

    private func settle(at position: MapCameraPosition) -> MapPanelCameraCompensation.Settle {
        MapPanelCameraCompensation.Settle(
            camera: MapCamera(centerCoordinate: seattle, distance: 1500, heading: 0, pitch: 0),
            mapPointsPerScreenPoint: scale,
            position: position
        )
    }

    /// The camera it settled on, as far away and facing the same way, recentred.
    @Test func `A sheet settling on its own gets the settled camera, recentred`() throws {
        let framed = MapCameraPosition.region(MKCoordinateRegion(center: seattle, latitudinalMeters: 1000, longitudinalMeters: 1000))

        let position = MapPanelCameraCompensation.compensatedPosition(for: framed, settle: settle(at: framed), paddingDelta: 100)

        let camera = try #require(position?.camera)
        #expect(camera.distance == 1500)
        #expect(camera.heading == 0)
        #expect(abs(mapPointOffset(from: seattle, to: camera.centerCoordinate).dy - -100.0) < 1e-6)
    }

    @Test func `Nothing is handed over without a settle, a change or with a framing since`() {
        let framed = MapCameraPosition.region(MKCoordinateRegion(center: seattle, latitudinalMeters: 1000, longitudinalMeters: 1000))
        let reframed = MapCameraPosition.region(MKCoordinateRegion(center: seattle, latitudinalMeters: 300, longitudinalMeters: 300))

        #expect(MapPanelCameraCompensation.compensatedPosition(for: framed, settle: nil, paddingDelta: 100) == nil)
        #expect(MapPanelCameraCompensation.compensatedPosition(for: framed, settle: settle(at: framed), paddingDelta: 0) == nil)
        #expect(MapPanelCameraCompensation.compensatedPosition(for: reframed, settle: settle(at: framed), paddingDelta: 100) == nil)
    }
}
