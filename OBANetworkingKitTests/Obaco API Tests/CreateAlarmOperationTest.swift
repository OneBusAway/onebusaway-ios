//
//  CreateAlarmOperationTest.swift
//  OBANetworkingKitTests
//
//  Created by Aaron Brethorst on 10/17/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import Nimble
import OHHTTPStubs
@testable import OBANetworkingKit

class CreateAlarmOperationTest: OBATestCase {

    let secondsBefore = 600.0
    let stopID = "XO"
    let tripID = "XO"
    let serviceDate: Int64 = 1234567890
    let vehicleID = "XO"
    let stopSequence = 1337
    let userPushID = "XO"

    func testAlarmURLRequest() {
        let request = CreateAlarmOperation.buildURLRequest(secondsBefore: secondsBefore, stopID: stopID, tripID: tripID, serviceDate: serviceDate, vehicleID: vehicleID, stopSequence: stopSequence, userPushID: userPushID, regionID: obacoRegionID, baseURL: baseURL, queryItems: [])
        let body = String(data: request.httpBody!, encoding: .utf8)

        expect(body).to(contain("seconds_before=600"))
        expect(body).to(contain("stop_id=XO"))
        expect(body).to(contain("trip_id=XO"))
        expect(body).to(contain("service_date=1234567890"))
        expect(body).to(contain("vehicle_id=XO"))
        expect(body).to(contain("stop_sequence=1337"))
        expect(body).to(contain("user_push_id=XO"))
    }

    func testSuccessfulAlarmCreationRequest() {
        let apiPath = CreateAlarmOperation.buildAPIPath(regionID: obacoRegionID)

        stub(condition: isHost(self.obacoHost) &&
                        isPath(apiPath) &&
                        isMethodPOST()
        ) { _ in
            return self.JSONFile(named: "create_alarm.json")
        }

        waitUntil { done in
            self.obacoService.postAlarm(secondsBefore: self.secondsBefore, stopID: self.stopID, tripID: self.tripID, serviceDate: self.serviceDate, vehicleID: self.vehicleID, stopSequence: self.stopSequence, userPushID: self.userPushID) { op in

                let stringBody = String(data: op.data!, encoding: .utf8)!
                expect(stringBody) == "{\"url\": \"http://alerts.example.com/regions/1/alarms/1234567890\"}"

                done()
            }
        }
    }
}
