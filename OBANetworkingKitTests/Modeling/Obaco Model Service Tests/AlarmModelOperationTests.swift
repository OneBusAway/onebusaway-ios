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
        let createAPIPath = CreateAlarmOperation.buildAPIPath(regionID: obacoRegionID)

        stub(condition: isHost(self.obacoHost) &&
            isPath(createAPIPath) &&
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
        let deleteAPIPath = "/regions/1/alarms/1234567890"
        stub(condition: isHost(self.obacoHost) &&
            isPath(deleteAPIPath) &&
            isMethodDELETE()
        ) { _ in
            return OHHTTPStubsResponse(data: Data(), statusCode: 200, headers: nil)
        }

        let data = loadData(file: "create_alarm.json")
        let decoder = JSONDecoder.obacoServiceDecoder()
        let alarm = try! decoder.decode(Alarm.self, from: data)

        expect(alarm).toNot(beNil())

        waitUntil { done in
            let op = self.obacoModelService.deleteAlarm(alarm: alarm)
            op.completionBlock = {
                expect(op.success).to(beTrue())
                done()
            }
        }
    }
}
