//
//  PersistenceSituationTests.swift
//  OBAKitCoreTests
// 
//  Copyright © 2023 Open Transit Software Foundation.
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import GRDB
import XCTest
import Foundation
@testable import OBAKitCore

final class PersistenceSituationTests: OBAKitCorePersistenceTestCase {
    override func setUp() async throws {
        try await super.setUp()

        let data = try Fixtures.loadData(file: "arrival-and-departure-for-stop-MTS_11589.json")
        dataLoader.mock(URLString: "https://www.example.com/api/where/arrival-and-departure-for-stop/MTS_11589.json", with: data)
        let response = try await restAPIService.getTripArrivalDepartureAtStop(stopID: "MTS_11589", tripID: "trip123", serviceDate: Date(timeIntervalSince1970: 1234567890), vehicleID: "vehicle_123", stopSequence: 1)
        try await persistence.processAPIResponse(response)
    }

    func testSituationsForRoute() async throws {
        throw XCTSkip()
//        let situation = try await persistence.database.read { db in
//
//        }
    }

    func testSituationRelationships() async throws {
        struct SituationAndTimeWindows {
            let situation: Situation
            let timeWindows: [ActiveWindowSituationRelation]
            let publicationWindows: [PublicationWindowSituationRelation]
            let affectedEntities: [AffectedSituationRelation]
        }

        let _results: SituationAndTimeWindows? = try await persistence.database.read { db in
            guard let situation = try Situation.fetchOne(db, id: "MTS_RTA:11638227") else {
                return nil
            }

            let timeWindows = try situation.activeWindows.fetchAll(db)
            let publicationWindows = try situation.publicationWindows.fetchAll(db)
            let affectedEntities = try situation.affectedEntities.fetchAll(db)
            return SituationAndTimeWindows(situation: situation, timeWindows: timeWindows, publicationWindows: publicationWindows, affectedEntities: affectedEntities)
        }

        let results = try XCTUnwrap(_results)
        XCTAssertEqual(results.situation.id, "MTS_RTA:11638227")
        XCTAssertEqual(results.situation.description?.value, "Due to construction, the Washington St. off ramp from Pacific Highway will be closed Wednesday, October 17, from 6:30am - 6:30pm. Eastbound route 10 will detour, but will not miss any stops.")

        // Time Window
        XCTAssertEqual(results.timeWindows.count, 1)
        let timeWindow = try XCTUnwrap(results.timeWindows.first)
        XCTAssertEqual(timeWindow.situationID, "MTS_RTA:11638227")
        XCTAssertEqual(timeWindow.from, Date(timeIntervalSince1970: 1539781200))
        XCTAssertEqual(timeWindow.to, Date(timeIntervalSince1970: 1539826200))

        let _timeWindowBackReference = try await persistence.database.read { db in
            try timeWindow.situation.fetchOne(db)
        }
        let timeWindowBackReference = try XCTUnwrap(_timeWindowBackReference)
        XCTAssertEqual(timeWindowBackReference.id, "MTS_RTA:11638227")

        // Publication Window
        XCTAssertTrue(results.publicationWindows.isEmpty)

        // Affected Entities
        XCTAssertEqual(results.affectedEntities.count, 1)
        XCTAssertEqual(results.affectedEntities.first?.routeID, "MTS_10")
    }
}
