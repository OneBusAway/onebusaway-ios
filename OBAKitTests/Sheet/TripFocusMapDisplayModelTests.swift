//
//  TripFocusMapDisplayModelTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MapKit
import Testing
import OBAKitCore
@testable import OBAKit

/// What the panel's map draws for an open trip sheet, where its camera goes, and
/// how long the drawing lasts.
@MainActor
@Suite(.serialized)
final class TripFocusMapDisplayModelTests {

    private func owner(tripID: String = "trip_1") throws -> AppSheetRoute {
        .tripDetails(try Fixtures.tripConvertible(tripID: tripID))
    }

    /// A model showing a fresh focus, and the focus, so a test can push values
    /// through it the way the trip page does.
    private func show(
        _ content: TripMapFocus.Content?,
        userLocation: CLLocationCoordinate2D? = nil
    ) throws -> (TripFocusMapDisplayModel, TripMapFocus) {
        let model = TripFocusMapDisplayModel(userLocation: { userLocation })
        let focus = TripMapFocus()
        focus.apply(content)
        model.show(focus: focus, owner: try owner())
        return (model, focus)
    }

    // MARK: - What's drawn

    /// The page publishes its focus as soon as it loads, before the trip has: no
    /// shape, no stops, no vehicle. Until there is something to draw, the ambient
    /// stops stay.
    @Test func `A focus with nothing to draw yet keeps the ambient stops until the trip loads`() throws {
        let (model, focus) = try show(TripMapFocusFixture.content(shape: [], progress: nil))

        #expect(model.display == nil)
        #expect(model.isShowingTrip == false)

        focus.apply(TripMapFocusFixture.content(shape: TripMapFocusFixture.shape(), progress: nil))

        #expect(model.isShowingTrip)
    }

    @Test func `A trip in progress draws both halves, its stops and its vehicle, and hides the ambient stops`() throws {
        let coordinate = CLLocationCoordinate2D(latitude: 47, longitude: -122)
        let (model, _) = try show(TripMapFocusFixture.content(
            shape: TripMapFocusFixture.shape(),
            progress: 0.5,
            stops: [
                TripMapFocusFixture.row(0, stopID: "A", coordinate: coordinate, isPassed: true),
                TripMapFocusFixture.row(1, stopID: "B", coordinate: coordinate, isPassed: true, isVehicleHere: true),
                TripMapFocusFixture.row(2, stopID: "C", coordinate: coordinate, isUserStop: true)
            ],
            vehicle: try TripMapFocusFixture.vehicle()
        ))

        let display = try #require(model.display)
        #expect(model.isShowingTrip)
        #expect(display.spent != nil)
        #expect(display.ahead != nil)
        #expect(display.vehicle != nil)
        #expect(display.stops.map(\.id) == ["0-A", "1-B", "2-C"])
        // The stop the bus is at isn't behind it yet, as on the map tab.
        #expect(display.stops.map(\.isPassed) == [true, false, false])
        #expect(display.stops.map(\.isUserStop) == [false, false, true])
    }

    /// No reported progress is not zero progress: nothing is known to have been
    /// travelled, so none of the line is drawn as travelled.
    @Test func `A trip with no reported progress draws its whole shape as ahead`() throws {
        let (model, _) = try show(TripMapFocusFixture.content(shape: TripMapFocusFixture.shape(), progress: nil))

        let display = try #require(model.display)
        #expect(display.spent == nil)
        #expect(display.ahead?.core.pointCount == 5)
    }

    @Test func `Direction arrows run only along the part still ahead`() throws {
        let line = TripMapFocusFixture.shape()
        let (model, _) = try show(TripMapFocusFixture.content(shape: line, progress: 0.5))

        let arrows = try #require(model.display).arrows
        #expect(!arrows.isEmpty)
        #expect(arrows.allSatisfy { $0.coordinate.longitude > line[2].longitude })
    }

    @Test func `A stop with no location is skipped rather than faked`() throws {
        let (model, _) = try show(TripMapFocusFixture.content(
            shape: TripMapFocusFixture.shape(),
            progress: 0.5,
            stops: [
                TripMapFocusFixture.row(0, stopID: "A", coordinate: CLLocationCoordinate2D(latitude: 47, longitude: -122)),
                TripMapFocusFixture.row(1, stopID: "B", coordinate: nil)
            ]
        ))

        #expect(try #require(model.display).stops.map(\.id) == ["0-A"])
    }

    // MARK: - Camera

    @Test func `The first draw frames the bus and the rider together`() throws {
        let status = try TripMapFocusFixture.vehicle()
        let rider = CLLocationCoordinate2D(
            latitude: status.coordinate.latitude + 0.01,
            longitude: status.coordinate.longitude
        )

        let (model, _) = try show(
            TripMapFocusFixture.content(shape: TripMapFocusFixture.shape(), progress: 0.5, vehicle: status),
            userLocation: rider
        )

        let rect = try #require(model.cameraTarget).rect
        #expect(rect.contains(MKMapPoint(status.coordinate)))
        #expect(rect.contains(MKMapPoint(rider)))
    }

    /// Framing is once per trip. The position refreshes every 30s, and a camera
    /// that re-framed on each tick would snatch the map back from a rider who had
    /// panned away.
    @Test func `A refresh doesn't frame the camera again`() throws {
        let vehicle = try TripMapFocusFixture.vehicle()
        let (model, focus) = try show(
            TripMapFocusFixture.content(shape: TripMapFocusFixture.shape(), progress: 0.5, vehicle: vehicle)
        )
        #expect(model.cameraTarget != nil)
        model.consumeCameraTarget()

        focus.apply(TripMapFocusFixture.content(shape: TripMapFocusFixture.shape(), progress: 0.6, vehicle: vehicle))

        #expect(model.cameraTarget == nil)
        #expect(model.isShowingTrip)
    }

    /// The page hands its focus over every time it appears, including on the way
    /// back from a schedule or alarm sheet it presented. That mustn't start over.
    @Test func `The page reappearing doesn't frame the camera again`() throws {
        let (model, focus) = try show(TripMapFocusFixture.content(
            shape: TripMapFocusFixture.shape(),
            progress: 0.5,
            vehicle: try TripMapFocusFixture.vehicle()
        ))
        model.consumeCameraTarget()

        model.show(focus: focus, owner: try owner())

        #expect(model.cameraTarget == nil)
        #expect(model.isShowingTrip)
    }

    // MARK: - Lifetime

    /// A drag-down, Back and `popToRoot` all take the route off the stack, which
    /// is the signal the panel relies on to end the drawing.
    @Test func `The drawing ends when its trip sheet leaves the stack`() throws {
        let (model, _) = try show(TripMapFocusFixture.content(shape: TripMapFocusFixture.shape(), progress: 0.5))
        #expect(model.isShowingTrip)

        model.clearIfOwnerAbsent(from: [.home])

        #expect(model.display == nil)
        #expect(model.isShowingTrip == false)
    }

    /// A stop opened from the trip stacks above it. The trip is still open
    /// underneath, so it stays drawn.
    @Test func `The drawing stays while its trip sheet is anywhere on the stack`() throws {
        let (model, focus) = try show(TripMapFocusFixture.content(shape: TripMapFocusFixture.shape(), progress: 0.5))
        let trip = try owner()

        // Kept alive as the open page would keep it, so the stack alone decides.
        withExtendedLifetime(focus) {
            model.clearIfOwnerAbsent(from: [.home, trip, .stopDetails(stopID: "1_75403")])

            #expect(model.isShowingTrip)
        }
    }

    /// Only one trip sheet is ever open, because the bridge closes the open one
    /// before opening another. So a new trip takes the drawing over, frames the
    /// camera for itself, and leaves nothing of the old one to fall back to.
    @Test func `Showing another trip replaces the one drawn`() throws {
        let coordinate = CLLocationCoordinate2D(latitude: 47, longitude: -122)
        let (model, firstFocus) = try show(TripMapFocusFixture.content(
            shape: TripMapFocusFixture.shape(),
            progress: 0.5,
            stops: [TripMapFocusFixture.row(0, stopID: "A", coordinate: coordinate)]
        ))
        model.consumeCameraTarget()
        let first = try owner()
        let second = try owner(tripID: "trip_2")
        let secondFocus = TripMapFocus()
        secondFocus.apply(TripMapFocusFixture.content(tripID: "trip_2", shape: TripMapFocusFixture.shape(), progress: 0.5))

        // The first page stays alive, so only the model decides whether its trip
        // comes back once the second one closes.
        withExtendedLifetime(firstFocus) {
            model.show(focus: secondFocus, owner: second)

            #expect(model.owner == second)
            #expect(model.display?.stops.isEmpty == true)
            #expect(model.cameraTarget != nil)

            model.clearIfOwnerAbsent(from: [.home, first])

            #expect(model.owner == nil)
            #expect(model.isShowingTrip == false)
        }
    }

    @Test func `A cleared drawing stops listening to the page`() throws {
        let (model, focus) = try show(TripMapFocusFixture.content(shape: TripMapFocusFixture.shape(), progress: 0.5))

        model.clear()
        focus.apply(TripMapFocusFixture.content(shape: TripMapFocusFixture.shape(), progress: 0.6))

        #expect(model.display == nil)
    }
}
