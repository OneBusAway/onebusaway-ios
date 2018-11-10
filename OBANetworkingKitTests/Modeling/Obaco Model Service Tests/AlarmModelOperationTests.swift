//
//  AlarmModelOperationTests.swift
//  OBANetworkingKitTests
//
//  Created by Aaron Brethorst on 11/10/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import Nimble
import OHHTTPStubs
import CoreLocation
@testable import OBANetworkingKit

class AlarmModelOperationTests: OBATestCase {

    let secondsBefore = 600.0
    let stopID = "XO"
    let tripID = "XO"
    let serviceDate: Int64 = 1234567890
    let vehicleID = "XO"
    let stopSequence = 1337
    let userPushID = "XO"

    func testSuccessfulAlarmCreation() {
        let apiPath = CreateAlarmOperation.buildAPIPath(regionID: obacoRegionID)

        stub(condition: isHost(self.obacoHost) &&
            isPath(apiPath) &&
            isMethodPOST()
        ) { _ in
            return self.JSONFile(named: "create_alarm.json")
        }

        waitUntil { done in
            let op = self.obacoModelService.postAlarm(secondsBefore: self.secondsBefore, stopID: self.stopID, tripID: self.tripID, serviceDate: self.serviceDate, vehicleID: self.vehicleID, stopSequence: self.stopSequence, userPushID: self.userPushID)
            op.completionBlock = {
                let alarm = op.alarm!
                expect(alarm.url) == URL(string: "http://alerts.example.com/regions/1/alarms/1234567890")!
                done()
            }
        }
    }

    func testSuccessfulAlarmDeletion() {

    }
}
