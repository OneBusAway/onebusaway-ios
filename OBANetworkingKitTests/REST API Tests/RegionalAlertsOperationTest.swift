//
//  RegionalAlertsOperationTest.swift
//  OBANetworkingKitTests
//
//  Created by Aaron Brethorst on 10/12/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import UIKit

import XCTest
import Nimble
import OHHTTPStubs
@testable import OBANetworkingKit

class RegionalAlertsOperationTest: XCTestCase, OperationTest {
    override func tearDown() {
        super.tearDown()
        OHHTTPStubs.removeAllStubs()
    }

    func testRegionalAlertsAPIPath() {
        expect(RegionalAlertsOperation.buildAPIPath(agencyID: "Hello/World")) == "/api/gtfs_realtime/alerts-for-agency/Hello%2FWorld.pb"
    }

    func testSuccessfulStopsForRouteRequest() {
        let agencyID = "1"
        let apiPath = RegionalAlertsOperation.buildAPIPath(agencyID: agencyID)

        stub(condition: isHost(self.host) &&
            isPath(apiPath)
        ) { _ in
            return self.dataFile(named: "puget_sound_alerts.pb")
        }

        waitUntil { done in
            self.builder.getRegionalAlerts(agencyID: agencyID) { op in
                expect(op.data).toNot(beNil())
                done()
            }
        }
    }
}
