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
@testable import OBAKitCore
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
        #expect(model.vehicle != nil)
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

    /// A Stop sheet's trip goes on top of what's open, so a second trip can open
    /// over the first through one of its stops. Closing the second goes back to
    /// drawing the first, whose sheet is uncovered but never appears again to say so.
    @Test func `Closing a trip opened over another goes back to drawing the first`() throws {
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

        // The first page is still open under the second, so its focus is alive.
        withExtendedLifetime(firstFocus) {
            model.show(focus: secondFocus, owner: second)
            #expect(model.owner == second)
            #expect(model.display?.stops.isEmpty == true)
            // A different trip frames the camera for itself.
            #expect(model.cameraTarget != nil)

            model.clearIfOwnerAbsent(from: [.home, first, .stopDetails(stopID: "1_75403")])

            #expect(model.owner == first)
            #expect(model.display?.stops.map(\.id) == ["0-A"])
        }
    }

    /// A trip whose page is gone can't send another update, so its entry goes even
    /// while its route is still on the stack, and nothing is left drawn from it.
    @Test func `A trip whose page has gone stops being drawn`() throws {
        let (model, _) = try show(TripMapFocusFixture.content(shape: TripMapFocusFixture.shape(), progress: 0.5))
        let trip = try owner()
        #expect(model.isShowingTrip)

        model.clearIfOwnerAbsent(from: [.home, trip])

        #expect(model.owner == nil)
        #expect(model.isShowingTrip == false)
    }

    @Test func `A cleared drawing stops listening to the page`() throws {
        let (model, focus) = try show(TripMapFocusFixture.content(shape: TripMapFocusFixture.shape(), progress: 0.5))

        model.clear()
        focus.apply(TripMapFocusFixture.content(shape: TripMapFocusFixture.shape(), progress: 0.6))

        #expect(model.display == nil)
    }

    // MARK: - Estimated position

    private let alongShape = CLLocationCoordinate2D(latitude: 47, longitude: -121.975)

    /// The panel rebuilds its polylines on every `display`. A 1 Hz estimate must
    /// move only the vehicle.
    @Test func `An estimate moves the vehicle without redrawing the trip`() throws {
        let (model, focus) = try show(TripMapFocusFixture.content(
            shape: TripMapFocusFixture.shape(), progress: 0.2, vehicle: try TripMapFocusFixture.vehicle()
        ))
        // The first estimate moves the line's join to the marker; the ticks after
        // it, inside `splitRefreshInterval`, must not.
        focus.applyVehicleEstimate(TripMapFocusFixture.estimate(at: alongShape, progress: 0.2))
        var displays = 0
        let subscription = model.$display.dropFirst().sink { _ in displays += 1 }
        defer { subscription.cancel() }

        focus.applyVehicleEstimate(TripMapFocusFixture.estimate(at: alongShape, progress: 0.21, shouldSnap: false))

        #expect(displays == 0)
        #expect(model.vehicle?.coordinate.longitude == alongShape.longitude)
        expectClose(model.vehicle?.orientation, 0, within: 0.001)
    }

    @Test func `Without an estimate the vehicle is where the feed says`() throws {
        let status = try TripMapFocusFixture.vehicle()
        let (model, focus) = try show(TripMapFocusFixture.content(shape: TripMapFocusFixture.shape(), progress: 0.2, vehicle: status))
        focus.applyVehicleEstimate(TripMapFocusFixture.estimate(at: alongShape))

        focus.applyVehicleEstimate(nil)

        #expect(model.vehicle?.coordinate.latitude == status.coordinate.latitude)
        #expect(model.vehicle?.staleness == .live)
    }

    @Test func `A poll does not move an estimated vehicle back`() throws {
        let status = try TripMapFocusFixture.vehicle()
        let (model, focus) = try show(TripMapFocusFixture.content(shape: TripMapFocusFixture.shape(), progress: 0.2, vehicle: status))
        focus.applyVehicleEstimate(TripMapFocusFixture.estimate(at: alongShape))

        focus.apply(TripMapFocusFixture.content(shape: TripMapFocusFixture.shape(), progress: 0.25, vehicle: status))

        #expect(model.vehicle?.coordinate.longitude == alongShape.longitude)
    }

    @Test func `An estimate re-splits the panel's line at most every few seconds`() throws {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let (model, focus) = try show(TripMapFocusFixture.content(
            shape: TripMapFocusFixture.shape(), progress: 0.2, vehicle: try TripMapFocusFixture.vehicle()
        ))
        model.now = { now }

        func spentEnd() -> Double? {
            model.display?.spent.map { $0.core.points()[$0.core.pointCount - 1].coordinate.longitude }
        }

        focus.applyVehicleEstimate(TripMapFocusFixture.estimate(at: alongShape, progress: 0.6))
        expectClose(spentEnd(), -121.976, within: 0.0005)

        now += 2
        focus.applyVehicleEstimate(TripMapFocusFixture.estimate(at: alongShape, progress: 0.7, shouldSnap: false))
        expectClose(spentEnd(), -121.976, within: 0.0005)

        now += TripFocusMapLayer.splitRefreshInterval
        focus.applyVehicleEstimate(TripMapFocusFixture.estimate(at: alongShape, progress: 0.7, shouldSnap: false))
        expectClose(spentEnd(), -121.972, within: 0.0005)
    }
}

