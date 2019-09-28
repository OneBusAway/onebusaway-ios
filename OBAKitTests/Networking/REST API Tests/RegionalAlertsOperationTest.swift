//
//  RegionalAlertsOperationTest.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 10/12/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import Nimble
import OHHTTPStubs
@testable import OBAKit
@testable import OBAKitCore

class RegionalAlertsOperationTest: OBATestCase {
    func testRegionalAlertsAPIPath() {
        expect(RegionalAlertsOperation.buildRESTAPIPath(agencyID: "Hello/World")) == "/api/gtfs_realtime/alerts-for-agency/Hello%2FWorld.pb"
    }

    func testSuccessfulStopsForRouteRequest() {
        let agencyID = "1"
        let apiPath = RegionalAlertsOperation.buildRESTAPIPath(agencyID: agencyID)

        stub(condition: isHost(self.host) &&
            isPath(apiPath)
        ) { _ in
            return OHHTTPStubsResponse.dataFile(named: "puget_sound_alerts.pb")
        }

        waitUntil { done in
            let op = self.restService.getRegionalAlerts(agencyID: agencyID)
            op.completionBlock = {
                expect(op.data).toNot(beNil())
                done()
            }
        }
    }
}
