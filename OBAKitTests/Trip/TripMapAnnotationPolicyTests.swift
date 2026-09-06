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

    private func makeController(arrivalDeparture: ArrivalDeparture) -> TripViewController {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: OperationQueue(), dataLoader: dataLoader)
        return TripViewController(application: application, arrivalDeparture: arrivalDeparture)
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

    /// `viewFor` only applies the policy when `arrivalDeparture` is set. Building
    /// the controller from `TripConvertible(tripDetails:)` skipped that branch,
    /// so `canShowCallout` was just MKAnnotationView's default `false`.
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
}
