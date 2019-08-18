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

// swiftlint:disable force_try

class RegionalAlertsModelOperationTests: OBATestCase {

    func stubAPICalls() {
        stub(condition: isHost(host) && isPath(AgenciesWithCoverageOperation.apiPath)) { _ in
            return OHHTTPStubsResponse.JSONFile(named: "agencies_with_coverage.json")
        }

        stub(condition: isHost(host) && isPath(RegionalAlertsOperation.buildRESTAPIPath(agencyID: "1"))) { _ in
            return OHHTTPStubsResponse.dataFile(named: "puget_sound_alerts.pb")
        }

        stub(condition: isHost(host) && isPath(RegionalAlertsOperation.buildRESTAPIPath(agencyID: "98"))) { _ in
            return OHHTTPStubsResponse.dataFile(named: "puget_sound_alerts.pb")
        }
    }

    func testSuccessfulRequest() {
        stubAPICalls()

        let json = loadJSONDictionary(file: "agencies_with_coverage.json")
        let agencies = try! decodeModels(type: AgencyWithCoverage.self, json: json)

        waitUntil { (done) in
            let op = self.restModelService.getRegionalAlerts(agencies: agencies)
            op.completionBlock = {
                let alerts = op.agencyAlerts

                // abxoxo - is this right and expected?
                expect(alerts.count) == 2
                done()
            }
        }
    }
}
