//
//  AlarmModelOperationTests.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 11/10/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import Nimble
import CoreLocation
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_try force_cast

class AlarmModelOperationTests: OBATestCase {

    func testSuccessfulAlarmCreation() {
        let data = Fixtures.loadData(file: "create_alarm.json")
        let arrivalDeparture = try! Fixtures.loadRESTAPIPayload(type: ArrivalDeparture.self, fileName: "arrival-and-departure-for-stop-1_11420.json")

        let dataLoader = (obacoService.dataLoader as! MockDataLoader)
        dataLoader.mock(URLString: "https://alerts.example.com/api/v1/regions/1/alarms", with: data)

        let op = obacoService.postAlarm(minutesBefore: 1, arrivalDeparture: arrivalDeparture, userPushID: "123")

        waitUntil { done in
            op.complete { result in
                switch result {
                case .failure(let error):
                    print("TODO FIXME handle error! \(error)")
                case .success(let response):
                    expect(response.url) == URL(string: "https://alerts.example.com/regions/1/alarms/1234567890")!
                    done()
                }
            }
        }
    }

    func testSuccessfulAlarmDeletion() {
        let alarm = try! Fixtures.loadAlarm()
        expect(alarm).toNot(beNil())

        let dataLoader = (obacoService.dataLoader as! MockDataLoader)
        dataLoader.mock(data: Data()) { (request) -> Bool in
            request.url!.absoluteString.starts(with: alarm.url.absoluteString) &&
            request.httpMethod == "DELETE"
        }

        waitUntil { done in
            let op = self.obacoService.deleteAlarm(url: alarm.url)

            let completion = BlockOperation {
                expect(op.response!.statusCode) == 200
                done()
            }
            completion.addDependency(op)
            self.obacoService.networkQueue.addOperation(completion)
        }
    }
}
