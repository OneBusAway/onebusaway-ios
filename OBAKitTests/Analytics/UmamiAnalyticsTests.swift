//
//  UmamiAnalyticsTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
@testable import App
@testable import OBAKitCore

final class UmamiAnalyticsTests: OBATestCase {

    private let successBody = #"{"cache":"x","sessionId":"s","visitId":"v"}"#.data(using: .utf8)!
    private let beepBoopBody = #"{"beep":"boop"}"#.data(using: .utf8)!

    private func makeReporter(loader: MockDataLoader) -> UmamiAnalytics {
        UmamiAnalytics(serverURL: URL(string: "https://analytics.example.com")!,
                       websiteID: "site-uuid",
                       hostname: "api.example.org",
                       dataLoader: loader)
    }

    // MARK: - path(from:)

    func testPathReduction() {
        expect(UmamiAnalytics.path(from: "app://localhost/map")) == "/map"
        expect(UmamiAnalytics.path(from: "app://localhost")) == "/"
        expect(UmamiAnalytics.path(from: "app://localhost/search?q=x")) == "/search"
    }

    // MARK: - isSuccessfulIngest

    func testSuccessDetection() {
        expect(UmamiAnalytics.isSuccessfulIngest(self.successBody)).to(beTrue())
        expect(UmamiAnalytics.isSuccessfulIngest(self.beepBoopBody)).to(beFalse())
        expect(UmamiAnalytics.isSuccessfulIngest("not json".data(using: .utf8)!)).to(beFalse())
    }

    // MARK: - UmamiJSONValue coercion

    func testJSONValueCoercion() {
        expect(UmamiJSONValue("hi")).toNot(beNil())
        expect(UmamiJSONValue(42)).toNot(beNil())
        // Non-JSON / non-finite values are dropped (nil), never crash.
        expect(UmamiJSONValue(Double.nan)).to(beNil())
        expect(UmamiJSONValue(nil)).to(beNil())
    }

    // MARK: - Request construction

    func testReportStopViewedBuildsContractRequest() async throws {
        let loader = MockDataLoader(testName: name)
        var captured: URLRequest?
        loader.mock(data: successBody) { request in
            captured = request
            return true
        }

        let reporter = makeReporter(loader: loader)
        await reporter.reportStopViewed(name: "Pine St", id: "1_75403", stopDistance: "near")

        let request = try XCTUnwrap(captured)
        expect(request.url?.absoluteString) == "https://analytics.example.com/api/send"
        expect(request.httpMethod) == "POST"
        expect(request.value(forHTTPHeaderField: "Content-Type")) == "application/json"

        // Explicit, non-bot User-Agent — full format: "OneBusAway/<version> (iOS <ver>; <model>)".
        let ua = try XCTUnwrap(request.value(forHTTPHeaderField: "User-Agent"))
        expect(ua).to(contain("OneBusAway/"))
        expect(ua).to(match("^OneBusAway/.+ \\(iOS .+; .+\\)$"))

        // Body matches the Umami contract.
        let body = try JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as! [String: Any]
        expect(body["type"] as? String) == "event"
        let payload = body["payload"] as! [String: Any]
        expect(payload["website"] as? String) == "site-uuid"
        expect(payload["hostname"] as? String) == "api.example.org"
        expect(payload["url"] as? String) == "/stop"
        expect(payload["name"]).to(beNil())   // pageview → no name
        let data = payload["data"] as! [String: Any]
        expect(data["id"] as? String) == "1_75403"
        expect(data["distance"] as? String) == "near"
    }

    func testReportEventIncludesName() async throws {
        let loader = MockDataLoader(testName: name)
        var captured: URLRequest?
        loader.mock(data: successBody) { request in
            captured = request
            return true
        }

        let reporter = makeReporter(loader: loader)
        await reporter.reportEvent(pageURL: "app://localhost/map", label: "Clicked MapStopIcon", value: nil)

        let request = try XCTUnwrap(captured)
        let body = try JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as! [String: Any]
        let payload = body["payload"] as! [String: Any]
        expect(payload["name"] as? String) == "Clicked MapStopIcon"
        expect(payload["url"] as? String) == "/map"
    }

    // MARK: - Fail-safe

    func testNonJSONValueDoesNotCrashOrThrow() async throws {
        let loader = MockDataLoader(testName: name)
        loader.mock(data: successBody) { _ in true }
        let reporter = makeReporter(loader: loader)
        // Double.nan is not representable; the event still emits without the value, no crash.
        await reporter.reportEvent(pageURL: "app://localhost/map", label: "x", value: Double.nan)
        // Confirm the event was still fired (unrepresentable value dropped, not the whole event).
        expect(loader.recordedRequestURLs.count) == 1
    }

    func testBeepBoopResponseIsSwallowed() async throws {
        let loader = MockDataLoader(testName: name)
        loader.mock(data: beepBoopBody) { _ in true }
        let reporter = makeReporter(loader: loader)
        // Should complete normally despite the dropped-event response.
        await reporter.reportSearchQuery("downtown")
        expect(loader.recordedRequestURLs.count) == 1
    }
}
