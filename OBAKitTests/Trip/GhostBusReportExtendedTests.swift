//
//  GhostBusReportExtendedTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class GhostBusReportExtendedTests: OBATestCase {

    @Test func `GhostBusReportDraft initializes with default wait duration`() {
        let serviceDate = Date(timeIntervalSince1970: 1600000000)
        let draft = GhostBusReportDraft(tripID: "trip_123", serviceDate: serviceDate)

        #expect(draft.tripID == "trip_123")
        #expect(draft.serviceDate == serviceDate)
        #expect(draft.waitDurationMinutes == 15)
        #expect(draft.routeID == nil)
        #expect(draft.stopID == nil)
        #expect(draft.vehicleID == nil)
        #expect(draft.stopSequence == nil)
        #expect(draft.predicted == nil)
        #expect(draft.scheduledArrivalAt == nil)
        #expect(draft.predictedArrivalAt == nil)
        #expect(draft.scheduleDeviationMinutes == nil)
        #expect(draft.predictionLastUpdatedAt == nil)
        #expect(draft.comment == nil)
        #expect(draft.userLatitude == nil)
        #expect(draft.userLongitude == nil)
    }

    @Test func `GhostBusReportDraft populates optional fields properly`() {
        let serviceDate = Date(timeIntervalSince1970: 1600000000)
        var draft = GhostBusReportDraft(tripID: "trip_456", serviceDate: serviceDate, waitDurationMinutes: 20)

        draft.routeID = "route_1"
        draft.stopID = "stop_99"
        draft.vehicleID = "veh_777"
        draft.stopSequence = 12
        draft.predicted = true
        draft.scheduledArrivalAt = Date(timeIntervalSince1970: 1600000300)
        draft.predictedArrivalAt = Date(timeIntervalSince1970: 1600000360)
        draft.scheduleDeviationMinutes = 1
        draft.predictionLastUpdatedAt = Date(timeIntervalSince1970: 1600000200)
        draft.comment = "Bus never showed up"
        draft.userLatitude = 47.6062
        draft.userLongitude = -122.3321

        #expect(draft.tripID == "trip_456")
        #expect(draft.waitDurationMinutes == 20)
        #expect(draft.routeID == "route_1")
        #expect(draft.stopID == "stop_99")
        #expect(draft.vehicleID == "veh_777")
        #expect(draft.stopSequence == 12)
        #expect(draft.predicted == true)
        #expect(draft.comment == "Bus never showed up")
        #expect(draft.userLatitude == 47.6062)
        #expect(draft.userLongitude == -122.3321)
    }

    @Test func `GhostBusReport decodes successfully from server response JSON`() throws {
        let json = """
        {
            "id": "report_abc123"
        }
        """.data(using: .utf8)!

        let report = try JSONDecoder().decode(GhostBusReport.self, from: json)
        #expect(report.id == "report_abc123")
    }

    @Test func `GhostBusReport encodes and roundtrips through JSONEncoder`() throws {
        let report = GhostBusReport(id: "rep_98765")
        let encoded = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(GhostBusReport.self, from: encoded)

        #expect(decoded.id == "rep_98765")
    }

    @Test func `GhostBusReportSubmissionError provides localized user-facing descriptions`() throws {
        let unavailableError = TripPageViewController.GhostBusReportSubmissionError.serviceUnavailable
        let reportedError = TripPageViewController.GhostBusReportSubmissionError.alreadyReported

        let unavailableDesc = try #require(unavailableError.errorDescription)
        let reportedDesc = try #require(reportedError.errorDescription)

        #expect(unavailableDesc.contains("service isn't available"))
        #expect(reportedDesc.contains("already been reported"))
    }
}
