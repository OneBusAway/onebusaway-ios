//
//  PlacemarkSearchOperationTest.swift
//  OBANetworkingKitTests
//
//  Created by Aaron Brethorst on 10/11/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import Nimble
import OHHTTPStubs
import MapKit
@testable import OBANetworkingKit

class PlacemarkSearchOperationTest: OBATestCase {
    func testPlacemarkSearch() {
        let center = CLLocationCoordinate2D(latitude: 47.623650, longitude: -122.312572)
        let span = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        let region = MKCoordinateRegion(center: center, span: span)

        waitUntil(timeout: 5.0) { done in
            self.builder.getPlacemarks(query: "Starbucks", region: region) { (op) in
                let mapItems = op.response!.mapItems
                expect(mapItems.count) > 0
                let starbucks = mapItems.first!
                expect(starbucks.name) == "Starbucks"
                expect(starbucks.phoneNumber?.starts(with: "‭+1 (206)")).to(beTrue())

                let region = op.response!.boundingRegion
                expect(region.center.latitude).to(beCloseTo(center.latitude, within: 0.1))
                expect(region.center.longitude).to(beCloseTo(center.longitude, within: 0.1))

                done()
            }
        }
    }
}
