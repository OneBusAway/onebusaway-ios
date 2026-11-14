//
//  StopRouteFocusEstimationTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import MapKit
import Testing
import UIKit
@testable import OBAKit
@testable import OBAKitCore

/// Estimated positions for the buses on a stop's map: each vehicle on its own
/// trip's shape, with its own trip's schedule.
@MainActor
@Suite(.serialized)
final class StopRouteFocusEstimationTests {
    typealias F = EstimationFixtures

    private let mapView = MKMapView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
    private let harness = StopEstimationHarness()
    private var clock: TestClock { harness.clock }
    private var layer: StopRouteFocusMapLayer!

    /// The fixture's first arrival, moved onto `F.straightLine()` 200 m along and
    /// given a fix time of `F.t0`.
    private let departure: ArrivalDeparture

    init() throws {
        departure = try #require(
            StopArrivalsFixture.upcoming(rewritingStatus: StopEstimationHarness.onShape).arrivalsAndDepartures.first
        )
    }

    private func makeLayer() -> StopRouteFocusMapLayer {
        let layer = StopRouteFocusMapLayer(
            mapView: mapView,
            shapeCache: harness.shapeCache,
            formatters: StopEstimationHarness.formatters,
            vehicleEstimation: harness.estimation
        )
        let departure = departure
        layer.departureProvider = { _ in departure }
        layer.begin(focus: StopMapFocus())
        self.layer = layer
        return layer
    }

    private func model() -> StopRouteFocusModel {
        StopRouteFocusModel(
            routes: [StopRouteFocusModel.DrawnRoute(routeID: "r", shortName: "R", color: .systemBlue, shapeID: "s", hasLiveVehicle: true)],
            vehicles: [StopRouteFocusModel.DrawnVehicle(
                id: "bus", routeID: "r",
                coordinate: CLLocationCoordinate2D(latitude: 47.65, longitude: -122.35),
                orientation: 90, departureID: "d",
                tripID: departure.tripID, shapeID: "s"
            )]
        )
    }

    private var marker: StopVehicleAnnotation? {
        mapView.annotations.compactMap { $0 as? StopVehicleAnnotation }.first
    }

    @Test func `An arriving bus is drawn at its estimate on its own trip's shape`() async throws {
        let layer = makeLayer()
        layer.update(model: model())
        await harness.estimation.inputsSettled()

        let marker = try #require(marker)
        expectClose(marker.coordinate.latitude, F.point(north: 200).latitude, within: 1e-5)
        expectClose(marker.coordinate.longitude, F.origin.longitude, within: 1e-5)
    }

    @Test func `The bus moves along between polls`() async throws {
        let layer = makeLayer()
        layer.update(model: model())
        await harness.estimation.inputsSettled()
        await poll(until: { self.clock.sleeperCount == 1 })

        harness.now += 10
        clock.advance(by: .seconds(1))
        await poll(until: { (self.marker?.coordinate.latitude ?? 0) > F.point(north: 250).latitude })

        expectClose(marker?.coordinate.latitude, F.point(north: 300).latitude, within: 1e-5)
    }

    @Test func `A poll does not drag an estimated bus back to the reported fix`() async throws {
        let layer = makeLayer()
        layer.update(model: model())
        await harness.estimation.inputsSettled()

        layer.update(model: model())

        expectClose(marker?.coordinate.latitude, F.point(north: 200).latitude, within: 1e-5)
    }

    @Test func `With estimation off no schedule is fetched and the bus is where the feed says`() async throws {
        harness.isEnabled = false
        let layer = makeLayer()
        layer.update(model: model())
        await harness.estimation.inputsSettled()

        #expect(await harness.scheduleFetches.count == 0)
        #expect(marker?.coordinate.latitude == 47.65)
    }

    @Test func `Each trip's schedule is fetched once across polls`() async throws {
        let layer = makeLayer()
        layer.update(model: model())
        await harness.estimation.inputsSettled()
        layer.update(model: model())
        await harness.estimation.inputsSettled()

        #expect(await harness.scheduleFetches.count == 1)
    }

    @Test func `A poll's server clock survives a refresh that cancels its gathering`() async throws {
        let layer = makeLayer()
        // The server is 10 s ahead of the device, so the bus is 10 s past its fix.
        let clock = ServerClockSample(serverTime: F.t0 + 10, receivedAt: F.t0)
        layer.apply(arrivals: nil, isListFiltered: false, preferences: StopPreferences(), serverClock: clock)
        // A second refresh before the first gathering has run, as a filter change makes.
        let departure = departure
        layer.departureProvider = { _ in departure }
        layer.update(model: model())
        await harness.estimation.inputsSettled()

        expectClose(marker?.coordinate.latitude, F.point(north: 300).latitude, within: 1e-5)
    }

    @Test func `Ending the presentation stops estimating`() async throws {
        let layer = makeLayer()
        layer.update(model: model())
        await harness.estimation.inputsSettled()
        await poll(until: { self.clock.sleeperCount == 1 })

        layer.end()

        await poll(until: { self.clock.sleeperCount == 0 }, "the tick should stop with the presentation")
    }
}
