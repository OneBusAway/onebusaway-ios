//
//  TripMapAnnotationPolicyTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
@testable import OBAKit
import Testing

@Suite(.serialized)
final class TripMapAnnotationPolicyTests {

    @Test func `Trip map suppresses stop callouts`() {
        #expect(!TripMapAnnotationPolicy.showsStopCallout)
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
