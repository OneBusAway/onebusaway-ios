//
//  AlarmModelOperationTests.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 11/10/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import Nimble
import OHHTTPStubs
import CoreLocation
@testable import OBAKit

// swiftlint:disable force_try

class AlarmModelOperationTests: OBATestCase {
    let minutesBefore = 1
    let userPushID = "123"

    func testSuccessfulAlarmCreation() {
        let createAPIPath = CreateAlarmOperation.buildAPIPath(regionID: obacoRegionID)

        let arrivalDeparture = try! ArrivalDeparture.decodeFromFile(named: "arrival-and-departure-for-stop-1_11420.json", in: Bundle(for: type(of: self))).first!

        stub(condition: isHost(self.obacoHost) &&
            isPath(createAPIPath) &&
            isMethodPOST()
        ) { _ in
            return OHHTTPStubsResponse.JSONFile(named: "create_alarm.json")
        }

        waitUntil { done in
            let op = self.obacoModelService.postAlarm(minutesBefore: self.minutesBefore, arrivalDeparture: arrivalDeparture, userPushID: self.userPushID)
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
