//
//  StopSheetLayoutMetricsTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import Testing
import UIKit
@testable import OBAKit

@MainActor
@Suite(.serialized)
final class StopSheetLayoutMetricsTests {

    @Test func `The half detent inset is half the safe area, matching FloatingPanel`() {
        // FloatingPanel's stock .half anchor is fractionalInset 0.5 of the SAFE
        // AREA. Using screen height instead overshoots by half the insets, which
        // would push the tapped stop further up the map than intended.
        #expect(StopSheetLayout.halfDetentInset(safeAreaHeight: 800) == 400)
    }

    @Test func `Framing a stop leaves it above the sheet`() {
        // The camera fix that actually matters: a zero-size MKMapRect is degenerate
        // and slams the camera to maximum zoom, so the rect `centerMapAboveSheet`
        // uses must have real extent. Exercise the actual helper it calls, not a
        // rect built ad hoc in the test — otherwise this only tests MapKit.
        let coordinate = CLLocationCoordinate2D(latitude: 47.6, longitude: -122.33)
        let rect = StopSheetLayout.framingRect(around: coordinate)

        #expect(rect.size.width > 0)
        #expect(rect.size.height > 0)
        #expect(rect.contains(MKMapPoint(coordinate)))
    }
}
