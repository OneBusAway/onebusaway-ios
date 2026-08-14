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
}
