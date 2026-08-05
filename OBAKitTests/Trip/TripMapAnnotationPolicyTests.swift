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

    @Test @MainActor
    func `Trip controller applies the no-callout policy to stop views`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: OperationQueue(), dataLoader: dataLoader)
        let tripDetails = try JSONDecoder.RESTDecoder().decode(
            RESTAPIResponse<TripDetails>.self,
            from: Fixtures.loadData(file: "trip_details_1_18196913.json")
        ).entry
        let controller = TripViewController(
            application: application,
            tripConvertible: TripConvertible(tripDetails: tripDetails)
        )
        let mapView = MKMapView()
        mapView.registerAnnotationView(MinimalStopAnnotationView.self)
        let stopTime = try #require(tripDetails.stopTimes.first)

        let view = try #require(controller.mapView(mapView, viewFor: stopTime) as? MinimalStopAnnotationView)

        #expect(!view.canShowCallout)
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
}
