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

// swiftlint:disable force_try

class RegionalAlertsModelOperationTests: OBATestCase {

    func stubAPICalls() {
        stub(condition: isHost(host) && isPath(AgenciesWithCoverageOperation.apiPath)) { _ in
            return OHHTTPStubsResponse.JSONFile(named: "agencies_with_coverage.json")
        }
        for id in ["1", "3", "19", "23", "29", "40", "95", "96", "97", "98", "KMD"] {
            stub(condition: isHost(host) && isPath(RegionalAlertsOperation.buildRESTAPIPath(agencyID: id))) { _ in
                return OHHTTPStubsResponse.dataFile(named: "puget_sound_alerts.pb")
            }
        }
    }

    func testSuccessfulRequest() {
        stubAPICalls()

        let agencies = try! AgencyWithCoverage.decodeFromFile(named: "agencies_with_coverage.json", in: Bundle(for: type(of: self)))

        waitUntil { (done) in
            let op = self.restModelService.getRegionalAlerts(agencies: agencies)
            op.completionBlock = {
                expect(op.agencyAlerts.count) == 20
                done()
            }
        }
    }
}
