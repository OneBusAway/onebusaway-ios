//
//  RegionalAlertsModelOperationTests.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 11/7/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import Nimble
import OHHTTPStubs
import CoreLocation
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_try force_cast

class RegionalAlertsModelOperationTests: OBATestCase {
    func testSuccessfulRequest() {
        let dataLoader = (restService.dataLoader as! MockDataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)

        let agencies = try! Fixtures.loadRESTAPIPayload(type: [AgencyWithCoverage].self, fileName: "agencies_with_coverage.json")
        let op = restService.getAlerts(agencies: agencies)

        waitUntil { (done) in
            op.complete { result in
                expect(result.count) == 20
                done()
            }
        }
    }
}
