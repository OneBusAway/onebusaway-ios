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

    private func makeController(arrivalDeparture: ArrivalDeparture, destinationStopID: StopID? = nil) -> TripViewController {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: OperationQueue(), dataLoader: dataLoader)
        return TripViewController(application: application, arrivalDeparture: arrivalDeparture, destinationStopID: destinationStopID)
    }

    private func loadTripDetails() throws -> TripDetails {
        try JSONDecoder.RESTDecoder().decode(
            RESTAPIResponse<TripDetails>.self,
            from: Fixtures.loadData(file: "trip_details_1_18196913.json")
        ).entry
    }

    /// An `ArrivalDeparture` with its references resolved. `Fixtures.arrivalDeparture()`
    /// leaves `route` nil, and anything that reaches `openStop` reads it through
    /// `TransferContext.from` — that crashed CI at `ArrivalDeparture.swift:221`.
    private func loadReferencedArrivalDeparture() throws -> ArrivalDeparture {
        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_10914.json"
        )
        return try #require(stopArrivals.arrivalsAndDepartures.first)
    }

    private func analytics(for controller: TripViewController) throws -> AnalyticsMock {
        try #require(controller.application.analytics as? AnalyticsMock)
    }

    private func stopAnnotationTapCount(_ analytics: AnalyticsMock) -> Int {
        analytics.reportedEvents.filter { $0.label == AnalyticsLabels.mapStopAnnotationTapped }.count
    }

    /// `viewFor` applies the policy to every stop view it hands MapKit.
    @Test @MainActor
    func `Trip controller applies the no-callout policy to stop views`() throws {
        let arrivalDeparture = try Fixtures.arrivalDeparture()
        let controller = makeController(arrivalDeparture: arrivalDeparture)
        let mapView = MKMapView()
        mapView.registerAnnotationView(MinimalStopAnnotationView.self)
        let stopTime = try #require(try loadTripDetails().stopTimes.first)

        let view = try #require(controller.mapView(mapView, viewFor: stopTime) as? MinimalStopAnnotationView)

        #expect(!view.canShowCallout)
        #expect(view.rightCalloutAccessoryView == nil)
        #expect(view.detailCalloutAccessoryView == nil)
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

    /// Opening a trip from a departure auto-selects the rider's stop. That
    /// programmatic select must not push the stop page back on top (#713).
    ///
    /// Do not load `controller.view`. `viewDidLoad` reads `ArrivalDeparture.route`,
    /// which `Fixtures.arrivalDeparture()` leaves unresolved, and spinning up the
    /// trip map plus floating panel crashed CI then hung the simulator for 10 minutes.
    /// `didSelect` is the production path under test; wrapping in a nav controller
    /// is enough for `ViewRouter.navigateTo` to push.
    @Test @MainActor
    func `Programmatic selection does not open the stop`() throws {
        let arrivalDeparture = try Fixtures.arrivalDeparture()
        let controller = makeController(arrivalDeparture: arrivalDeparture)
        let nav = UINavigationController(rootViewController: controller)

        let stopTime = try #require(try loadTripDetails().stopTimes.first)
        let annotationView = MinimalStopAnnotationView(annotation: stopTime, reuseIdentifier: "test")
        annotationView.canShowCallout = false

        controller.skipNextStopTimeHighlight = true
        controller.mapView(MKMapView(), didSelect: annotationView)

        #expect(nav.viewControllers.count == 1)
        #expect(nav.viewControllers.first === controller)
        #expect(stopAnnotationTapCount(try analytics(for: controller)) == 0)
    }

    /// A rider tap with callouts off still opens the stop, and reports the open —
    /// `MapViewController` reports the identical "selection is the open gesture" case.
    @Test @MainActor
    func `User tap opens the stop when callouts are hidden`() throws {
        let controller = makeController(arrivalDeparture: try loadReferencedArrivalDeparture())
        let nav = UINavigationController(rootViewController: controller)

        let stopTime = try #require(try loadTripDetails().stopTimes.first)
        let annotationView = MinimalStopAnnotationView(annotation: stopTime, reuseIdentifier: "test")
        annotationView.canShowCallout = false

        controller.skipNextStopTimeHighlight = false
        controller.mapView(MKMapView(), didSelect: annotationView)

        #expect(nav.viewControllers.count == 2)

        let reported = try #require(try analytics(for: controller).reportedEvents.first)
        #expect(reported.label == AnalyticsLabels.mapStopAnnotationTapped)
        #expect(reported.pageURL == "app://localhost/trip")
    }

    /// `$tripDetails` republishes every 30s, and the origin select is applied on the
    /// first emission only. `selectedStopTime = nil` is the production teardown: the
    /// load-time select fires `didSelect`, which consumes the skip, deselects the pin,
    /// and `didDeselect` clears the property. A later emission must leave that nil
    /// alone — writing origin back would fire `didSelect` → `openStop` and push the
    /// stop page out from under the rider. Do not load `.view`.
    @Test @MainActor
    func `Refresh does not reselect the origin stop`() throws {
        let details = try loadTripDetails()
        let originID = try #require(details.stopTimes.first?.stopID)
        let arrivalDeparture = try Fixtures.arrivalDeparture(stopID: originID)
        let controller = makeController(arrivalDeparture: arrivalDeparture)

        controller.applyOriginStopSelection(from: details)
        #expect(controller.selectedStopTime?.stopID == originID)

        controller.selectedStopTime = nil
        controller.applyOriginStopSelection(from: details)

        #expect(controller.selectedStopTime == nil)
        #expect(!controller.skipNextStopTimeHighlight)
    }

    /// A trip with no stop time for the rider's boarding stop selects nothing — and,
    /// just as importantly, arms nothing. `skipNextStopTimeHighlight` is armed at the
    /// `selectAnnotation` call site, so an assignment that finds no annotation cannot
    /// leave an arm behind to swallow the rider's next pin tap. Do not load `.view`.
    @Test @MainActor
    func `No origin selection when the trip has no matching stop`() throws {
        let details = try loadTripDetails()
        let controller = makeController(arrivalDeparture: try Fixtures.arrivalDeparture(stopID: "no_such_stop"))

        controller.applyOriginStopSelection(from: details)

        #expect(controller.selectedStopTime == nil)
        #expect(!controller.skipNextStopTimeHighlight)
    }

    /// Callouts are off, so selection is the only open gesture. Leaving the
    /// pin selected after `openStop` (or after the load-time skip) means
    /// MapKit will not fire `didSelect` again. Use the `mapView` MapKit
    /// passed in — not `self.mapView`, which would load `.view`.
    @Test @MainActor
    func `Opening a stop deselects the pin so a second tap still opens`() throws {
        let controller = makeController(arrivalDeparture: try loadReferencedArrivalDeparture())
        let nav = UINavigationController(rootViewController: controller)
        let mapView = MKMapView()
        let stopTime = try #require(try loadTripDetails().stopTimes.first)
        mapView.addAnnotation(stopTime)
        mapView.selectAnnotation(stopTime, animated: false)

        let annotationView = MinimalStopAnnotationView(annotation: stopTime, reuseIdentifier: "test")
        annotationView.canShowCallout = false

        controller.skipNextStopTimeHighlight = false
        controller.mapView(mapView, didSelect: annotationView)

        #expect(mapView.selectedAnnotations.isEmpty)
        #expect(nav.viewControllers.count == 2)

        mapView.selectAnnotation(stopTime, animated: false)
        controller.mapView(mapView, didSelect: annotationView)

        #expect(mapView.selectedAnnotations.isEmpty)
        #expect(nav.viewControllers.count == 3)
    }

    /// Load-time `selectAnnotation` arms skip and must still deselect, or
    /// the first tap on the origin pin is a no-op.
    @Test @MainActor
    func `Programmatic selection deselects so the origin pin can be tapped`() throws {
        let arrivalDeparture = try Fixtures.arrivalDeparture()
        let controller = makeController(arrivalDeparture: arrivalDeparture)
        let mapView = MKMapView()
        let stopTime = try #require(try loadTripDetails().stopTimes.first)
        mapView.addAnnotation(stopTime)
        mapView.selectAnnotation(stopTime, animated: false)

        let annotationView = MinimalStopAnnotationView(annotation: stopTime, reuseIdentifier: "test")
        controller.skipNextStopTimeHighlight = true
        controller.mapView(mapView, didSelect: annotationView)

        #expect(mapView.selectedAnnotations.isEmpty)
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

    /// The controller marks the pins MapKit asks it for from the trip's own
    /// arrival and the shared destination, and puts the destination's arrival on
    /// the destination's pin. Do not load `.view`.
    @Test @MainActor
    func `A shared trip's map marks its boarding and destination pins`() throws {
        let details = try loadTripDetails()
        let boarding = details.stopTimes[boardingRow]
        let destination = details.stopTimes[destinationRow]
        let controller = makeController(
            arrivalDeparture: try Fixtures.arrivalDeparture(stopSequence: boardingRow, stopID: boarding.stopID),
            destinationStopID: destination.stopID
        )
        let mapView = MKMapView()
        mapView.registerAnnotationView(MinimalStopAnnotationView.self)

        controller.applyStopMarks(from: details)
        controller.applyDestinationArrival(try Fixtures.arrivalDeparture(stopSequence: destinationRow, stopID: destination.stopID))

        // The fixture's route is unresolved, so the marks fall back to the brand color.
        let markColor = ThemeColors.shared.brand.cgColor

        let destinationView = try #require(controller.mapView(mapView, viewFor: destination) as? MinimalStopAnnotationView)
        #expect(destinationView.bounds.width == 16)
        #expect(try shapeLayer(of: destinationView).fillColor == markColor)
        #expect(try !arrivalBadge(of: destinationView).isHidden)
        #expect(destinationView.zPriority == .max)

        let boardingView = try #require(controller.mapView(mapView, viewFor: boarding) as? MinimalStopAnnotationView)
        #expect(boardingView.bounds.width == 16)
        #expect(try shapeLayer(of: boardingView).strokeColor == markColor)
        #expect(try shapeLayer(of: boardingView).fillColor == UIColor.white.cgColor)
        #expect(try arrivalBadge(of: boardingView).isHidden)
        #expect(boardingView.zPriority == .defaultUnselected)

        let ordinaryView = try #require(controller.mapView(mapView, viewFor: details.stopTimes[0]) as? MinimalStopAnnotationView)
        #expect(ordinaryView.bounds.width == 10)
        #expect(try arrivalBadge(of: ordinaryView).isHidden)
        #expect(ordinaryView.zPriority == .defaultUnselected)
    }

    /// A refresh applies new trip details before fetching the replacement
    /// destination arrival. `applyStopMarks(from:)` clears the retained destination
    /// arrival so stale arrival predictions are not shown on new details. See #1513.
    @Test @MainActor
    func `Applying stop marks clears the retained destination arrival`() throws {
        let details = try loadTripDetails()
        let boarding = details.stopTimes[boardingRow]
        let destination = details.stopTimes[destinationRow]
        let controller = makeController(
            arrivalDeparture: try Fixtures.arrivalDeparture(stopSequence: boardingRow, stopID: boarding.stopID),
            destinationStopID: destination.stopID
        )
        let mapView = MKMapView()
        mapView.registerAnnotationView(MinimalStopAnnotationView.self)

        controller.applyStopMarks(from: details)
        controller.applyDestinationArrival(try Fixtures.arrivalDeparture(stopSequence: destinationRow, stopID: destination.stopID))

        let destinationView = try #require(controller.mapView(mapView, viewFor: destination) as? MinimalStopAnnotationView)
        #expect(try !arrivalBadge(of: destinationView).isHidden)
        #expect(destinationView.zPriority == .max)

        // Refreshed details arrive before the replacement arrival:
        controller.applyStopMarks(from: details)
        let refreshedView = try #require(controller.mapView(mapView, viewFor: destination) as? MinimalStopAnnotationView)
        #expect(try arrivalBadge(of: refreshedView).isHidden)
        #expect(refreshedView.zPriority == .defaultUnselected)
    }

    /// Refreshed trip details clear any retained destination arrival so the
    /// progress header does not calculate its countdown using stale arrival data. See #1513.
    @Test @MainActor
    func `Updating trip details clears the progress header destination arrival`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: OperationQueue(), dataLoader: dataLoader)
        let panel = TripFloatingPanelController(application: application)
        panel.destinationArrivalDeparture = try Fixtures.arrivalDeparture()

        #expect(panel.destinationArrivalDeparture != nil)

        panel.tripDetails = try loadTripDetails()

        #expect(panel.destinationArrivalDeparture == nil)
    }
}
