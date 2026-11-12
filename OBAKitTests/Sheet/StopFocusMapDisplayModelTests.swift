//
//  StopFocusMapDisplayModelTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// The panel's counterpart of `StopRouteFocusMapLayer`: an open stop sheet's routes
/// and live vehicles, drawn on the panel's SwiftUI map.
@MainActor
@Suite(.serialized)
final class StopFocusMapDisplayModelTests {

    private static let formatters = Formatters(
        locale: Locale(identifier: "en_US"),
        calendar: Calendar(identifier: .gregorian),
        themeColors: ThemeColors.shared
    )

    private static let stop = AppSheetRoute.stopDetails(stopID: "1_10020")
    private static let otherStop = AppSheetRoute.stopDetails(stopID: "1_99999")

    private static func encodedLine() -> String {
        Polyline(coordinates: [
            CLLocationCoordinate2D(latitude: 47.60, longitude: -122.33),
            CLLocationCoordinate2D(latitude: 47.61, longitude: -122.34),
            CLLocationCoordinate2D(latitude: 47.62, longitude: -122.35)
        ]).encodedPolyline
    }

    private func makeModel(shape: String = encodedLine()) -> StopFocusMapDisplayModel {
        StopFocusMapDisplayModel(shapeCache: ShapeCache { _ in shape }, formatters: Self.formatters)
    }

    private func showFixture(
        on model: StopFocusMapDisplayModel,
        owner: AppSheetRoute = stop,
        focus: StopMapFocus = StopMapFocus()
    ) async throws {
        model.show(focus: focus, owner: owner)
        model.apply(arrivals: try StopArrivalsFixture.upcoming(), isListFiltered: false, preferences: StopPreferences(), owner: owner)
        await model.awaitPendingShapeWork()
    }

    // MARK: - What draws

    /// The rider's complaint: a stop opened from Recent or Bookmarks showed no buses.
    @Test func `An open stop draws its live vehicles`() async throws {
        let model = makeModel()
        try await showFixture(on: model)

        let display = try #require(model.display)
        #expect(display.vehicles.count == 4)
        #expect(Set(display.vehicles.map(\.routeID)) == ["1_30", "1_65"])
        #expect(display.vehicles.allSatisfy { $0.isRealTime })
    }

    @Test func `An open stop draws a line for each of its routes once the shapes load`() async throws {
        let model = makeModel()
        try await showFixture(on: model)

        let display = try #require(model.display)
        #expect(display.routes.map(\.id).sorted() == ["1_30", "1_65"])
        // More than the shape's three points: both routes share all of it, so their
        // lines are resampled to move a lane over.
        #expect(display.routes.allSatisfy { $0.line.core.pointCount >= 3 })
    }

    /// A shape that fails to load costs that route's line, not its buses.
    @Test func `Vehicles draw even when no shape loads`() async throws {
        let model = makeModel(shape: "")
        try await showFixture(on: model)

        let display = try #require(model.display)
        #expect(display.routes.isEmpty)
        #expect(display.vehicles.count == 4)
    }

    /// The sheet's route chips decorate themselves from the focus, as they do over
    /// the map tab. Over the panel they used to stay plain because nothing fed it.
    @Test func `The stop sheet's chips learn which routes are drawn`() async throws {
        let model = makeModel()
        let focus = StopMapFocus()
        try await showFixture(on: model, focus: focus)

        #expect(focus.routes.map(\.routeID).sorted() == ["1_30", "1_65"])
        #expect(focus.isFocusable(routeID: "1_30"))
    }

    @Test func `Arrivals for a stop that was never shown draw nothing`() throws {
        let model = makeModel()
        model.apply(arrivals: try StopArrivalsFixture.upcoming(), isListFiltered: false, preferences: StopPreferences(), owner: Self.stop)
        #expect(model.display == nil)
    }

    @Test func `Vehicle markers carry a VoiceOver label naming the route and vehicle`() async throws {
        let model = makeModel()
        try await showFixture(on: model)

        let vehicle = try #require(model.display?.vehicles.first { $0.id == "1_7028" })
        #expect(vehicle.accessibilityLabel.contains("1_7028"))
        #expect(vehicle.departure.vehicleID == "1_7028")
    }

    // MARK: - Shared streets

    /// Both fixture routes load the same shape, so they share every street of it.
    /// On the map tab they draw side by side (#1569); the panel has to as well.
    @Test func `Routes sharing a street draw side by side once the zoom is known`() async throws {
        let model = makeModel()
        try await showFixture(on: model)
        model.updateScreenScale(Self.screenScale)

        let routes = try #require(model.display?.routes)
        try #require(routes.count == 2)
        #expect(Self.middle(of: routes[0]).distance(to: Self.middle(of: routes[1])) > 0)
    }

    @Test func `Zooming far enough lays the lanes out again`() async throws {
        let model = makeModel()
        try await showFixture(on: model)
        model.updateScreenScale(Self.screenScale)
        let before = try #require(model.display?.routes.first.map { Self.middle(of: $0) })

        model.updateScreenScale(Self.screenScale * 4)

        let after = try #require(model.display?.routes.first.map { Self.middle(of: $0) })
        #expect(before.distance(to: after) > 0)
    }

    @Test func `A small zoom keeps the lanes where they are`() async throws {
        let model = makeModel()
        try await showFixture(on: model)
        model.updateScreenScale(Self.screenScale)
        let before = try #require(model.display?.routes.first.map { Self.middle(of: $0) })

        model.updateScreenScale(Self.screenScale * 1.05)

        let after = try #require(model.display?.routes.first.map { Self.middle(of: $0) })
        #expect(before.distance(to: after) == 0)
    }

    /// Screen points per map point at about zoom 16 in Seattle.
    private static let screenScale: CGFloat = 1 / (0.3 * MKMapPointsPerMeterAtLatitude(47.61))

    private static func middle(of route: StopFocusMapDisplayModel.RouteLine) -> MKMapPoint {
        let polyline = route.line.core
        return polyline.points()[polyline.pointCount / 2]
    }

    // MARK: - Focus

    @Test func `Focusing a route dims the others`() async throws {
        let model = makeModel()
        let focus = StopMapFocus()
        try await showFixture(on: model, focus: focus)

        focus.focus(routeID: "1_30")

        let display = try #require(model.display)
        #expect(display.routes.first { $0.id == "1_30" }?.emphasis == .focused)
        #expect(display.routes.first { $0.id == "1_65" }?.emphasis == .dimmed)
        #expect(display.vehicles.filter { $0.routeID == "1_65" }.allSatisfy { $0.emphasis == .dimmed })

        focus.clearFocus()
        #expect(model.display?.routes.allSatisfy { $0.emphasis == .normal } == true)
    }

    // MARK: - Lifetime

    @Test func `Closing the stop sheet clears the map`() async throws {
        let model = makeModel()
        try await showFixture(on: model)

        model.clearIfOwnerAbsent(from: [.home])

        #expect(model.display == nil)
        #expect(model.owner == nil)
    }

    /// Stop → trip → another stop: the newer stop draws, and closing it hands the map
    /// back to the first one with its own routes, not the second stop's.
    @Test func `A stop opened over another takes the map until it closes`() async throws {
        let model = makeModel()
        // Held here because the model holds them weakly, as the sheets own them.
        let firstFocus = StopMapFocus()
        let secondFocus = StopMapFocus()
        try await showFixture(on: model, owner: Self.stop, focus: firstFocus)
        model.show(focus: secondFocus, owner: Self.otherStop)

        #expect(model.owner == Self.otherStop)
        #expect(model.display == nil, "The second stop has no arrivals yet")

        model.clearIfOwnerAbsent(from: [.home, Self.stop])
        await model.awaitPendingShapeWork()

        #expect(model.owner == Self.stop)
        #expect(model.display?.vehicles.count == 4)
        withExtendedLifetime((firstFocus, secondFocus)) {}
    }

    /// A covered stop sheet keeps refreshing. Its arrivals must not draw over the
    /// stop on top.
    @Test func `A covered stop's refresh doesn't draw over the one on top`() async throws {
        let model = makeModel()
        let firstFocus = StopMapFocus()
        let secondFocus = StopMapFocus()
        model.show(focus: firstFocus, owner: Self.stop)
        model.show(focus: secondFocus, owner: Self.otherStop)

        model.apply(arrivals: try StopArrivalsFixture.upcoming(), isListFiltered: false, preferences: StopPreferences(), owner: Self.stop)
        await model.awaitPendingShapeWork()

        #expect(model.display == nil)
        withExtendedLifetime((firstFocus, secondFocus)) {}
    }

    /// The sheet reports its focus every time it appears; starting over would
    /// throw away what's drawn.
    @Test func `Showing the same focus again keeps what's drawn`() async throws {
        let model = makeModel()
        let focus = StopMapFocus()
        try await showFixture(on: model, focus: focus)

        model.show(focus: focus, owner: Self.stop)

        #expect(model.display?.vehicles.count == 4)
    }

    // MARK: - Sharing the map with an open trip

    @Test func `A stop draws when no trip is open`() {
        #expect(StopFocusMapDisplayModel.stopTakesMap(stopOwner: Self.stop, tripOwner: nil, routes: [.home, Self.stop]))
    }

    private func tripRoute() throws -> AppSheetRoute {
        let departure = try #require(try StopArrivalsFixture.load().arrivalsAndDepartures.first)
        return .tripDetails(TripConvertible(arrivalDeparture: departure))
    }

    @Test func `A trip opened over the stop takes the map`() throws {
        let trip = try tripRoute()
        #expect(!StopFocusMapDisplayModel.stopTakesMap(stopOwner: Self.stop, tripOwner: trip, routes: [.home, Self.stop, trip]))
    }

    /// Stop → trip → another stop: the newest sheet is the one the rider is looking at.
    @Test func `A stop opened over the trip takes the map back`() throws {
        let trip = try tripRoute()
        #expect(StopFocusMapDisplayModel.stopTakesMap(stopOwner: Self.otherStop, tripOwner: trip, routes: [.home, Self.stop, trip, Self.otherStop]))
    }

    @Test func `No stop sheet, nothing to draw`() {
        #expect(!StopFocusMapDisplayModel.stopTakesMap(stopOwner: nil, tripOwner: nil, routes: [.home]))
    }
}
