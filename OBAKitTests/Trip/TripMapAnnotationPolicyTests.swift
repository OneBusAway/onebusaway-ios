//
//  TripMapAnnotationPolicyTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MapKit
@testable import OBAKit
@testable import OBAKitCore
import Testing

@Suite(.serialized)
final class TripMapAnnotationPolicyTests: OBATestCase {
    private func loadTripDetails() throws -> TripDetails {
        try JSONDecoder.RESTDecoder().decode(
            RESTAPIResponse<TripDetails>.self,
            from: Fixtures.loadData(file: "trip_details_1_18196913.json")
        ).entry
    }

    @Test @MainActor
    func `Applying policy clears callout accessories`() {
        let view = MinimalStopAnnotationView(annotation: nil, reuseIdentifier: "test")
        view.canShowCallout = true
        view.rightCalloutAccessoryView = UIButton.chevronButton
        view.detailCalloutAccessoryView = UILabel.autolayoutNew()

        TripMapAnnotationPolicy.apply(to: view)

        #expect(!view.canShowCallout)
        #expect(view.rightCalloutAccessoryView == nil)
        #expect(view.detailCalloutAccessoryView == nil)
    }

    // MARK: - Stop marks (#449)

    // In trip_details_1_18196913, row 8 is stop 1_29915 and row 29 is 1_26000.
    private let boardingRow = 8
    private let destinationRow = 29

    private func stopMarks(destinationIndex: Int?, destinationArrival: ArrivalDeparture? = nil) throws -> TripMapAnnotationPolicy.StopMarks {
        var marks = TripMapAnnotationPolicy.StopMarks()
        marks.stopTimes = try loadTripDetails().stopTimes
        marks.riderStops = TripStopListModel.RiderStops(boardingIndex: boardingRow, destinationIndex: destinationIndex)
        marks.destinationArrival = destinationArrival
        return marks
    }

    private func markedRows(_ marks: TripMapAnnotationPolicy.StopMarks) -> [Int] {
        marks.stopTimes.indices.filter { marks.marking(for: marks.stopTimes[$0]) != .ordinary }
    }

    private func shapeLayer(of view: MinimalStopAnnotationView) throws -> CAShapeLayer {
        try #require(view.layer.sublayers?.compactMap { $0 as? CAShapeLayer }.first)
    }

    private func arrivalBadge(of view: MinimalStopAnnotationView) throws -> DepartureTimeBadge {
        try #require(view.subviews.compactMap { $0 as? DepartureTimeBadge }.first)
    }

    private let sevenMinutes = DepartureTimeBadge.Configuration(
        accessibilityLabel: "arrives in 7 minutes",
        displayText: "7m",
        backgroundColor: UIColor.green.cgColor
    )

    /// A trip that was never shared marks its boarding stop as the rider's, and
    /// shows no arrival on any pin, even with one to hand.
    @Test @MainActor
    func `Without a shared destination only the boarding stop is marked`() throws {
        let marks = try stopMarks(destinationIndex: nil, destinationArrival: try Fixtures.arrivalDeparture())

        #expect(markedRows(marks) == [boardingRow])
        #expect(marks.marking(for: marks.stopTimes[boardingRow]) == .riderStop)
        #expect(marks.stopTimes.allSatisfy { marks.arrival(for: $0) == nil })
    }

    /// A shared trip moves the rider's mark to the destination, as the stop list
    /// does, and keeps a boarding mark where the sharer gets on.
    @Test @MainActor
    func `A shared trip marks its destination as the rider's stop and keeps its boarding stop marked`() throws {
        let marks = try stopMarks(destinationIndex: destinationRow)

        #expect(markedRows(marks) == [boardingRow, destinationRow])
        #expect(marks.marking(for: marks.stopTimes[destinationRow]) == .riderStop)
        #expect(marks.marking(for: marks.stopTimes[boardingRow]) == .boardingStop)
    }

    /// The destination's arrival goes on the destination's pin and no other, and
    /// only once it has loaded.
    @Test @MainActor
    func `Only the destination's pin shows its arrival`() throws {
        let unloaded = try stopMarks(destinationIndex: destinationRow)
        #expect(unloaded.stopTimes.allSatisfy { unloaded.arrival(for: $0) == nil })

        let arrival = try Fixtures.arrivalDeparture(stopSequence: destinationRow, stopID: "1_26000")
        let marks = try stopMarks(destinationIndex: destinationRow, destinationArrival: arrival)
        let destination = marks.stopTimes[destinationRow]

        #expect(marks.arrival(for: destination) === arrival)
        #expect(marks.stopTimes.filter { marks.arrival(for: $0) != nil } == [destination])
    }

    /// A refresh keeps the pins whose stop times did not change, so a pin's
    /// annotation is often an instance from an earlier load. It must still find
    /// its row in the latest one.
    @Test @MainActor
    func `A pin from an earlier load finds its row in the latest`() throws {
        let marks = try stopMarks(destinationIndex: destinationRow)
        let earlierLoad = try loadTripDetails().stopTimes

        #expect(earlierLoad[destinationRow] !== marks.stopTimes[destinationRow])
        #expect(marks.marking(for: earlierLoad[destinationRow]) == .riderStop)
        #expect(marks.marking(for: earlierLoad[boardingRow]) == .boardingStop)
    }

    /// Before the trip's details load there are no rows to match, so no pin is
    /// marked and none shows an arrival.
    @Test @MainActor
    func `Before a load no pin is marked`() throws {
        var unloaded = TripMapAnnotationPolicy.StopMarks()
        unloaded.riderStops = TripStopListModel.RiderStops(boardingIndex: boardingRow, destinationIndex: destinationRow)
        unloaded.destinationArrival = try Fixtures.arrivalDeparture()
        let marks = unloaded
        let stopTime = try loadTripDetails().stopTimes[destinationRow]

        #expect(marks.marking(for: stopTime) == .ordinary)
        #expect(marks.arrival(for: stopTime) == nil)
    }

    /// The rider's stop is a larger dot filled with the route's color, with its
    /// arrival centred above it.
    @Test @MainActor
    func `The rider's stop pin is filled with the route color and shows its arrival above`() throws {
        let view = MinimalStopAnnotationView(annotation: nil, reuseIdentifier: "test")

        view.configure(marking: .riderStop, routeColor: .red, arrival: sevenMinutes)
        view.layoutIfNeeded()

        #expect(view.bounds.size == CGSize(width: 16, height: 16))
        let shape = try shapeLayer(of: view)
        #expect(shape.fillColor == UIColor.red.cgColor)
        #expect(shape.strokeColor == UIColor.white.cgColor)
        #expect(shape.lineWidth == 2.5)

        let badge = try arrivalBadge(of: view)
        #expect(!badge.isHidden)
        #expect(badge.text == "7m")
        #expect(badge.frame.maxY < view.bounds.minY)
        #expect(abs(badge.frame.midX - view.bounds.midX) < 0.001)
        // VoiceOver reads the pin, not the badge, so the pin carries the arrival.
        #expect(view.accessibilityValue == "arrives in 7 minutes")
        #expect(view.zPriority == .max)
    }

    /// On a shared trip the sharer's boarding stop is a ring in the route's
    /// color: marked, without claiming to be the rider's stop.
    @Test @MainActor
    func `The boarding stop pin is a ring in the route color`() throws {
        let view = MinimalStopAnnotationView(annotation: nil, reuseIdentifier: "test")

        view.configure(marking: .boardingStop, routeColor: .red, arrival: nil)

        #expect(view.bounds.size == CGSize(width: 16, height: 16))
        let shape = try shapeLayer(of: view)
        #expect(shape.fillColor == UIColor.white.cgColor)
        #expect(shape.strokeColor == UIColor.red.cgColor)
        #expect(try arrivalBadge(of: view).isHidden)
        #expect(view.accessibilityValue == nil)
        #expect(view.zPriority == .defaultUnselected)
    }

    /// A reused view must not carry the last stop's mark or arrival to the next.
    @Test @MainActor
    func `Reuse clears a pin's mark and arrival`() throws {
        let view = MinimalStopAnnotationView(annotation: nil, reuseIdentifier: "test")
        view.configure(marking: .riderStop, routeColor: .red, arrival: sevenMinutes)

        view.prepareForReuse()

        #expect(view.bounds.size == CGSize(width: 10, height: 10))
        let shape = try shapeLayer(of: view)
        #expect(shape.fillColor == UIColor.white.cgColor)
        #expect(shape.strokeColor == UIColor.gray.cgColor)
        #expect(shape.lineWidth == 1)

        let badge = try arrivalBadge(of: view)
        #expect(badge.isHidden)
        #expect(badge.text == nil)
        #expect(view.zPriority == .defaultUnselected)
    }

}
