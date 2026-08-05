//
//  GhostBusReportOperationTests.swift
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

// swiftlint:disable force_cast

@Suite(.serialized)
final class GhostBusReportOperationTests: OBATestCase {

    private final class RequestCapture: @unchecked Sendable {
        nonisolated(unsafe) var body: String?
    }

    private func makeDraft() -> GhostBusReportDraft {
        var draft = GhostBusReportDraft(
            tripID: "1_604825",
            serviceDate: Date(timeIntervalSince1970: 1_754_352_000)
        )
        draft.routeID = "1_100223"
        draft.stopID = "1_75403"
        draft.vehicleID = "1_4361"
        draft.stopSequence = 12
        draft.predicted = true
        draft.scheduleDeviationMinutes = 2
        draft.waitDurationMinutes = 15
        draft.comment = "Watched it disappear off the map."
        return draft
    }

    @Test func `Successful ghost bus report submission`() async throws {
        let data = Fixtures.loadData(file: "create_ghost_bus_report.json")
        let dataLoader = (obacoService.dataLoader as! MockDataLoader)
        dataLoader.mock(URLString: "https://alerts.example.com/api/v2/regions/1/ghost_bus_reports", with: data)

        let report = try await obacoService.postGhostBusReport(makeDraft(), userID: "device-uuid-1")
        #expect(report.id == "c0ffee00c0ffee00c0ff")
    }

    @Test func `Submission sends the captured trip context form-encoded`() async throws {
        let data = Fixtures.loadData(file: "create_ghost_bus_report.json")
        let capture = RequestCapture()
        let dataLoader = (obacoService.dataLoader as! MockDataLoader)
        dataLoader.mock(data: data) { request in
            guard request.httpMethod == "POST", request.url?.path.hasSuffix("/ghost_bus_reports") ?? false else {
                return false
            }
            capture.body = request.httpBody.flatMap { String(data: $0, encoding: .utf8) }
            return true
        }

        _ = try await obacoService.postGhostBusReport(makeDraft(), userID: "device-uuid-1")

        let body = try #require(capture.body)
        #expect(body.contains("user_identifier=device-uuid-1"))
        #expect(body.contains("trip_identifier=1_604825"))
        #expect(body.contains("service_date=1754352000000"))
        #expect(body.contains("wait_duration_minutes=15"))
        #expect(body.contains("predicted=1"))
        #expect(body.contains("vehicle_identifier=1_4361"))
        #expect(body.contains("stop_sequence=12"))
    }

    @Test func `Optional fields are omitted, not sent empty`() async throws {
        let data = Fixtures.loadData(file: "create_ghost_bus_report.json")
        let capture = RequestCapture()
        let dataLoader = (obacoService.dataLoader as! MockDataLoader)
        dataLoader.mock(data: data) { request in
            capture.body = request.httpBody.flatMap { String(data: $0, encoding: .utf8) }
            return request.httpMethod == "POST"
        }

        let minimal = GhostBusReportDraft(tripID: "1_604825", serviceDate: Date(timeIntervalSince1970: 1_754_352_000))
        _ = try await obacoService.postGhostBusReport(minimal, userID: "device-uuid-1")

        let body = try #require(capture.body)
        #expect(!body.contains("vehicle_identifier"))
        #expect(!body.contains("comment"))
        #expect(!body.contains("predicted"))
        #expect(!body.contains("user_latitude"))
    }

    @Test func `Comment with form-special characters is strictly escaped, not corrupted`() async throws {
        let data = Fixtures.loadData(file: "create_ghost_bus_report.json")
        let capture = RequestCapture()
        let dataLoader = (obacoService.dataLoader as! MockDataLoader)
        dataLoader.mock(data: data) { request in
            capture.body = request.httpBody.flatMap { String(data: $0, encoding: .utf8) }
            return request.httpMethod == "POST"
        }

        var draft = makeDraft()
        draft.comment = "Sat 20+ min & it vanished = gone; really"
        _ = try await obacoService.postGhostBusReport(draft, userID: "device-uuid-1")

        let body = try #require(capture.body)

        // `.urlQueryAllowed` (the bug) leaves &, +, ;, and = unescaped, which would
        // truncate the comment param at the first & and turn + into a space server-side.
        // A strictly-escaped comment value must contain none of those raw characters.
        let commentParam = try #require(body.components(separatedBy: "&").first { $0.hasPrefix("comment=") })
        let commentValue = String(commentParam.dropFirst("comment=".count))
        #expect(!commentValue.contains("&"))
        #expect(!commentValue.contains("+"))
        #expect(!commentValue.contains("="))
        #expect(!commentValue.contains(";"))

        // Percent-decoding the escaped value recovers the original comment exactly.
        let decoded = commentValue.removingPercentEncoding
        #expect(decoded == "Sat 20+ min & it vanished = gone; really")

        // Other params must still be intact and unaffected by the comment's encoding.
        #expect(body.contains("user_identifier=device-uuid-1"))
        #expect(body.contains("trip_identifier=1_604825"))
    }
}
