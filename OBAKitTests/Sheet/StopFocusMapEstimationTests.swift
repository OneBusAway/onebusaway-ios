//
//  StopFocusMapEstimationTests.swift
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

/// Estimated positions for the buses on an open stop's panel map, from the same
/// `StopVehicleEstimation` the map tab's `StopRouteFocusMapLayer` uses; see
/// `StopRouteFocusEstimationTests`.
@MainActor
@Suite(.serialized)
final class StopFocusMapEstimationTests {
    typealias F = EstimationFixtures

    private static let stop = AppSheetRoute.stopDetails(stopID: "1_10020")

    private let harness = StopEstimationHarness()
    private var clock: TestClock { harness.clock }
    /// Held here because the model holds it weakly, as the sheet owns it.
    private let focus = StopMapFocus()

    private func makeModel() -> StopFocusMapDisplayModel {
        StopFocusMapDisplayModel(
            shapeCache: harness.shapeCache,
            formatters: StopEstimationHarness.formatters,
            vehicleEstimation: harness.estimation
        )
    }

    /// Every vehicle 200 m along `F.straightLine()`, with a fix time of `F.t0`.
    private static func arrivals() throws -> StopArrivals {
        try StopArrivalsFixture.upcoming(rewritingStatus: StopEstimationHarness.onShape)
    }

    private func show(_ model: StopFocusMapDisplayModel, serverClock: ServerClockSample? = nil) async throws {
        model.show(focus: focus, owner: Self.stop)
        model.apply(
            arrivals: try Self.arrivals(), isListFiltered: false, preferences: StopPreferences(),
            serverClock: serverClock, owner: Self.stop
        )
        await model.awaitPendingShapeWork()
        await harness.estimation.inputsSettled()
    }

    /// The vehicles running the trip they're arriving on. The fixture's others are
    /// still finishing their previous trips, so they have no fix on the arriving
    /// trip's shape to estimate from, and stay where the feed says.
    private func onTheirTrips(_ model: StopFocusMapDisplayModel) -> [StopFocusMapDisplayModel.Vehicle] {
        (model.display?.vehicles ?? []).filter { $0.departure.tripStatus?.activeTripID == $0.departure.tripID }
    }

    private func latitudes(_ model: StopFocusMapDisplayModel) -> [Double] {
        onTheirTrips(model).map(\.coordinate.latitude)
    }

    @Test func `Arriving buses are drawn at their estimates on their own trips' shapes`() async throws {
        let model = makeModel()
        try await show(model)

        let vehicles = onTheirTrips(model)
        #expect(vehicles.count == 2)
        for vehicle in vehicles {
            expectClose(vehicle.coordinate.latitude, F.point(north: 200).latitude, within: 1e-5)
            expectClose(vehicle.coordinate.longitude, F.origin.longitude, within: 1e-5)
            #expect(vehicle.staleness == .live)
        }
    }

    @Test func `A bus still on its previous trip stays where the feed says`() async throws {
        let model = makeModel()
        try await show(model)

        let others = (model.display?.vehicles ?? []).filter { $0.departure.tripStatus?.activeTripID != $0.departure.tripID }
        #expect(others.count == 2)
        for vehicle in others {
            #expect(abs(vehicle.coordinate.latitude - F.point(north: 200).latitude) > 1e-3)
        }
    }

    @Test func `The buses move along between polls`() async throws {
        let model = makeModel()
        try await show(model)
        await poll(until: { self.clock.sleeperCount == 1 })

        harness.now += 10
        clock.advance(by: .seconds(1))
        await poll(until: { self.latitudes(model).allSatisfy { $0 > F.point(north: 250).latitude } })

        for latitude in latitudes(model) {
            expectClose(latitude, F.point(north: 300).latitude, within: 1e-5)
        }
    }

    @Test func `A poll does not drag an estimated bus back to the reported fix`() async throws {
        let model = makeModel()
        try await show(model)
        await poll(until: { self.clock.sleeperCount == 1 })
        harness.now += 10
        clock.advance(by: .seconds(1))
        await poll(until: { self.latitudes(model).allSatisfy { $0 > F.point(north: 250).latitude } })

        model.apply(arrivals: try Self.arrivals(), isListFiltered: false, preferences: StopPreferences(), owner: Self.stop)

        for latitude in latitudes(model) {
            #expect(latitude > F.point(north: 250).latitude)
        }
    }

    @Test func `The response's server clock dates the estimate`() async throws {
        let model = makeModel()
        // The server is 10 s ahead of the device, so the buses are 10 s past their fixes.
        try await show(model, serverClock: ServerClockSample(serverTime: F.t0 + 10, receivedAt: F.t0))

        for latitude in latitudes(model) {
            expectClose(latitude, F.point(north: 300).latitude, within: 1e-5)
        }
    }

    @Test func `With estimation off no schedule is fetched and the buses are where the feed says`() async throws {
        harness.isEnabled = false
        let model = makeModel()
        try await show(model)

        #expect(await harness.scheduleFetches.count == 0)
        #expect(clock.sleeperCount == 0)
        let vehicles = try #require(model.display?.vehicles)
        #expect(vehicles.allSatisfy { $0.staleness == .live })
    }

    @Test func `A trip taking the map stops the stop's estimates, and giving it back restarts them`() async throws {
        let model = makeModel()
        try await show(model)
        await poll(until: { self.clock.sleeperCount == 1 })

        model.setSuppressed(true)
        await poll(until: { self.clock.sleeperCount == 0 }, "the tick should stop while the trip has the map")

        model.setSuppressed(false)
        await harness.estimation.inputsSettled()
        await poll(until: { self.clock.sleeperCount == 1 }, "the tick should come back with the map")
    }

    @Test func `Closing the stop sheet stops estimating`() async throws {
        let model = makeModel()
        try await show(model)
        await poll(until: { self.clock.sleeperCount == 1 })

        model.clearIfOwnerAbsent(from: [.home])

        await poll(until: { self.clock.sleeperCount == 0 }, "the tick should stop with the sheet")
        #expect(model.display == nil)
    }
}
