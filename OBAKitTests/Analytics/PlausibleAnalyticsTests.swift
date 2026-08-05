//
//  PlausibleAnalyticsTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import AviaryInsights
@testable import App

/// Records Plausible events so `PlausibleAnalytics` can be tested without a network.
private actor RecordingPlausibleClient: PlausibleEventClient {
    private(set) var events: [Event] = []

    func postEvent(_ event: Event) async throws {
        events.append(event)
    }
}

@Suite(.serialized)
final class PlausibleAnalyticsTests: OBATestCase {

    // MARK: - sendablePropValue coercion
    //
    // Mirrors the @objc Analytics bridge: Int/Double/Bool arrive as NSNumber;
    // unknown types stringify. Matches UmamiAnalyticsTests JSON-value coercion
    // in spirit, for Plausible's Sendable prop path (#1199).

    @Test func `Sendable prop value passes String through`() {
        let value = PlausibleAnalytics.sendablePropValue(from: "hello")
        #expect(value as? String == "hello")
    }

    @Test func `Sendable prop value passes NSNumber through`() {
        #expect(
            PlausibleAnalytics.sendablePropValue(from: NSNumber(value: 42)) as? NSNumber
                == NSNumber(value: 42)
        )
        #expect(
            PlausibleAnalytics.sendablePropValue(from: NSNumber(value: 3.5)) as? NSNumber
                == NSNumber(value: 3.5)
        )
        #expect(
            PlausibleAnalytics.sendablePropValue(from: NSNumber(value: true)) as? NSNumber
                == NSNumber(value: true)
        )
    }

    @Test func `Sendable prop value nil stays nil`() {
        #expect(PlausibleAnalytics.sendablePropValue(from: nil) == nil)
    }

    @Test func `Sendable prop value unknown types stringify`() {
        struct Token: CustomStringConvertible {
            var description: String { "token-42" }
        }
        #expect(PlausibleAnalytics.sendablePropValue(from: Token()) as? String == "token-42")
    }

    // MARK: - Injectable client seam

    @Test func `Report event posts typed props to client`() async {
        let client = RecordingPlausibleClient()
        let analytics = PlausibleAnalytics(client: client)

        await analytics.reportEvent(pageURL: "app://localhost/map", label: "count", value: NSNumber(value: 7))

        let events = await client.events
        #expect(events.count == 1)
        let event = events[0]
        #expect(event.url == "app://localhost/map")
        #expect(event.props?["count"] as? NSNumber == NSNumber(value: 7))
    }

    @Test func `Report search query posts string prop`() async {
        let client = RecordingPlausibleClient()
        let analytics = PlausibleAnalytics(client: client)

        await analytics.reportSearchQuery("downtown")

        let events = await client.events
        #expect(events.count == 1)
        #expect(events[0].url == "app://localhost/search")
        #expect(events[0].props?["query"] as? String == "downtown")
    }

    /// Production `reportStopViewed` posts `id` and `distance` and silently
    /// discards `name` — assert the props that ship, not the unused parameter.
    @Test func `Report stop viewed posts id and distance`() async {
        let client = RecordingPlausibleClient()
        let analytics = PlausibleAnalytics(client: client)

        await analytics.reportStopViewed(name: "Pine St", id: "1_75403", stopDistance: "near")

        let events = await client.events
        #expect(events.count == 1)
        #expect(events[0].url == "app://localhost/stop")
        #expect(events[0].props?["id"] as? String == "1_75403")
        #expect(events[0].props?["distance"] as? String == "near")
        // `name` is intentionally not forwarded today.
        #expect(events[0].props?["name"] == nil)
        #expect(!(events[0].props?.keys.contains("name") ?? false))
    }

    @Test func `Default properties merge into posted event`() async {
        let client = RecordingPlausibleClient()
        let analytics = PlausibleAnalytics(client: client)
        analytics.setUserProperty(key: "RegionName", value: "Puget Sound")

        await analytics.reportEvent(pageURL: "app://localhost/map", label: "tap", value: nil)

        let events = await client.events
        #expect(events.count == 1)
        #expect(events[0].props?["RegionName"] as? String == "Puget Sound")
        // A nil event value still keeps the label key present (AviaryInsights
        // boxes Optional.none). Dictionary subscript can't tell "nil value"
        // from "missing key" — assert presence instead.
        #expect(events[0].props?.keys.contains("tap") == true)
    }
}
