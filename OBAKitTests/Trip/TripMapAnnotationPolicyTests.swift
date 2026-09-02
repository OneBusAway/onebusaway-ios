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
    }

    /// A rider tap with callouts off still opens the stop.
    ///
    /// Needs a referenced `ArrivalDeparture`: `openStop` builds `TransferContext.from`,
    /// which reads `routeShortName`. `Fixtures.arrivalDeparture()` leaves `route` nil
    /// and crashed CI at `ArrivalDeparture.swift:221`.
    @Test @MainActor
    func `User tap opens the stop when callouts are hidden`() throws {
        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_10914.json"
        )
        let arrivalDeparture = try #require(stopArrivals.arrivalsAndDepartures.first)
        let controller = makeController(arrivalDeparture: arrivalDeparture)
        let nav = UINavigationController(rootViewController: controller)

        let stopTime = try #require(try loadTripDetails().stopTimes.first)
        let annotationView = MinimalStopAnnotationView(annotation: stopTime, reuseIdentifier: "test")
        annotationView.canShowCallout = false

        controller.skipNextStopTimeHighlight = false
        controller.mapView(MKMapView(), didSelect: annotationView)

        #expect(nav.viewControllers.count == 2)
    }

    /// `$tripDetails` republishes every 30s. Re-assigning origin on every
    /// emission is a value-equal write, so `didSet` must drop a leaked skip
    /// arm — otherwise the next pin tap is swallowed. Do not load `.view`.
    /// Does not tap-to-open: `Fixtures.arrivalDeparture` leaves `route` nil.
    @Test @MainActor
    func `Value-equal origin refresh clears a leaked skip arm`() throws {
        let details = try loadTripDetails()
        let originID = try #require(details.stopTimes.first?.stopID)
        let arrivalDeparture = try Fixtures.arrivalDeparture(stopID: originID)
        let controller = makeController(arrivalDeparture: arrivalDeparture)

        controller.applyOriginStopSelection(from: details)
        #expect(controller.skipNextStopTimeHighlight)
        #expect(controller.selectedStopTime?.stopID == originID)

        controller.applyOriginStopSelection(from: details)
        #expect(!controller.skipNextStopTimeHighlight)
        #expect(controller.selectedStopTime?.stopID == originID)
    }

    /// After the rider deselects (or picks another stop), a 30s refresh must
    /// not write the origin back. That re-select would fire `didSelect` →
    /// `openStop`. Setting `selectedStopTime = nil` is the production
    /// `didDeselect` assignment. Do not load `.view`.
    @Test @MainActor
    func `Refresh does not reselect origin after the rider deselects`() throws {
        let details = try loadTripDetails()
        let originID = try #require(details.stopTimes.first?.stopID)
        let arrivalDeparture = try Fixtures.arrivalDeparture(stopID: originID)
        let controller = makeController(arrivalDeparture: arrivalDeparture)

        controller.applyOriginStopSelection(from: details)
        #expect(controller.selectedStopTime?.stopID == originID)

        controller.selectedStopTime = nil
        controller.applyOriginStopSelection(from: details)

        #expect(controller.selectedStopTime == nil)
    }

    /// Callouts are off, so selection is the only open gesture. Leaving the
    /// pin selected after `openStop` (or after the load-time skip) means
    /// MapKit will not fire `didSelect` again. Use the `mapView` MapKit
    /// passed in — not `self.mapView`, which would load `.view`.
    @Test @MainActor
    func `Opening a stop deselects the pin so a second tap still opens`() throws {
        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_10914.json"
        )
        let arrivalDeparture = try #require(stopArrivals.arrivalsAndDepartures.first)
        let controller = makeController(arrivalDeparture: arrivalDeparture)
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
