//
//  UmamiAnalyticsTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import App
@testable import OBAKitCore

@Suite(.serialized)
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

    @Test func `Path reduction`() {
        #expect(UmamiAnalytics.path(from: "app://localhost/map") == "/map")
        #expect(UmamiAnalytics.path(from: "app://localhost") == "/")
        #expect(UmamiAnalytics.path(from: "app://localhost/search?q=x") == "/search")
    }

    // MARK: - isSuccessfulIngest

    @Test func `Success detection`() {
        #expect(UmamiAnalytics.isSuccessfulIngest(self.successBody))
        #expect(!UmamiAnalytics.isSuccessfulIngest(self.beepBoopBody))
        #expect(!UmamiAnalytics.isSuccessfulIngest("not json".data(using: .utf8)!))
    }

    // MARK: - UmamiJSONValue coercion

    @Test func `JSON value coercion`() {
        #expect(UmamiJSONValue("hi") != nil)
        #expect(UmamiJSONValue(42) != nil)
        // Non-JSON / non-finite values are dropped (nil), never crash.
        #expect(UmamiJSONValue(Double.nan) == nil)
        #expect(UmamiJSONValue(nil) == nil)
    }

    // MARK: - Request construction

    @Test func `Report stop viewed builds contract request`() async throws {
        let loader = MockDataLoader(testName: name)
        // Boxed: the matcher is @Sendable and runs off the main actor, so it
        // cannot write to a main-actor-isolated local.
        let captured = SendableBox<URLRequest?>(nil)
        loader.mock(data: successBody) { request in
            captured.value = request
            return true
        }

        let reporter = makeReporter(loader: loader)
        await reporter.reportStopViewed(name: "Pine St", id: "1_75403", stopDistance: "near")

        let request = try #require(captured.value)
        #expect(request.url?.absoluteString == "https://analytics.example.com/api/send")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        // Explicit, non-bot User-Agent — full format: "OneBusAway/<version> (iOS <ver>; <model>)".
        let ua = try #require(request.value(forHTTPHeaderField: "User-Agent"))
        #expect(ua.contains("OneBusAway/"))
        #expect(NSPredicate(format: "SELF MATCHES %@", "^OneBusAway/.+ \\(iOS .+; .+\\)$").evaluate(with: ua))

        // Body matches the Umami contract.
        let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as! [String: Any]
        #expect((body["type"] as? String) == "event")
        let payload = body["payload"] as! [String: Any]
        #expect((payload["website"] as? String) == "site-uuid")
        #expect((payload["hostname"] as? String) == "api.example.org")
        #expect((payload["url"] as? String) == "/stop")
        #expect(payload["name"] == nil)  // pageview → no name
        let data = payload["data"] as! [String: Any]
        #expect((data["id"] as? String) == "1_75403")
        #expect((data["distance"] as? String) == "near")
    }

    @Test func `Report event includes name`() async throws {
        let loader = MockDataLoader(testName: name)
        // Boxed: the matcher is @Sendable and runs off the main actor, so it
        // cannot write to a main-actor-isolated local.
        let captured = SendableBox<URLRequest?>(nil)
        loader.mock(data: successBody) { request in
            captured.value = request
            return true
        }

        let reporter = makeReporter(loader: loader)
        await reporter.reportEvent(pageURL: "app://localhost/map", label: "Clicked MapStopIcon", value: nil)

        let request = try #require(captured.value)
        let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as! [String: Any]
        let payload = body["payload"] as! [String: Any]
        #expect((payload["name"] as? String) == "Clicked MapStopIcon")
        #expect((payload["url"] as? String) == "/map")
    }

    // MARK: - Fail-safe

    @Test func `Non JSON value does not crash or throw`() async throws {
        let loader = MockDataLoader(testName: name)
        loader.mock(data: successBody) { _ in true }
        let reporter = makeReporter(loader: loader)
        // Double.nan is not representable; the event still emits without the value, no crash.
        await reporter.reportEvent(pageURL: "app://localhost/map", label: "x", value: Double.nan)
        // Confirm the event was still fired (unrepresentable value dropped, not the whole event).
        #expect(loader.recordedRequestURLs.count == 1)
    }

    @Test func `Beep boop response is swallowed`() async throws {
        let loader = MockDataLoader(testName: name)
        loader.mock(data: beepBoopBody) { _ in true }
        let reporter = makeReporter(loader: loader)
        // Should complete normally despite the dropped-event response.
        await reporter.reportSearchQuery("downtown")
        #expect(loader.recordedRequestURLs.count == 1)
    }
}
