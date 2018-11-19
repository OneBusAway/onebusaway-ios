//
//  RegionalAlertsModelOperationTests.swift
//  OBANetworkingKitTests
//
//  Created by Aaron Brethorst on 11/7/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import Nimble
import OHHTTPStubs
import CoreLocation
import OBATestHelpers
@testable import OBANetworkingKit

class RegionalAlertsModelOperationTests: OBATestCase {

    func stubAPICalls() {
        stub(condition: isHost(host) && isPath(AgenciesWithCoverageOperation.apiPath)) { _ in
            return self.JSONFile(named: "agencies_with_coverage.json")
        }

        stub(condition: isHost(host) && isPath(RegionalAlertsOperation.buildAPIPath(agencyID: "1"))) { _ in
            return self.dataFile(named: "puget_sound_alerts.pb")
        }

        stub(condition: isHost(host) && isPath(RegionalAlertsOperation.buildAPIPath(agencyID: "98"))) { _ in
            return self.dataFile(named: "puget_sound_alerts.pb")
        }
    }

    func testSuccessfulRequest() {
        stubAPICalls()

        waitUntil { (done) in
            let op = self.restModelService.getRegionalAlerts()
            op.completionBlock = {
                let alerts = op.agencyAlerts

                // abxoxo - is this right and expected?
                expect(alerts.count) == 2
                done()
            }
        }
    }
}
