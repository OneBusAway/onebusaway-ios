//
//  PlausibleAnalytics.swift
//  App
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKit
import AviaryInsights

/// Seam for posting Plausible events. Production uses `AviaryInsights.Plausible`;
/// tests inject a recording double (#1199).
///
/// Explicitly `nonisolated`: App's default MainActor isolation would otherwise
/// make this protocol MainActor-bound, which blocks both `Plausible` (a plain
/// Sendable struct) and actor-based test doubles from conforming (CI Xcode 27).
nonisolated protocol PlausibleEventClient: Sendable {
    func postEvent(_ event: Event) async throws
}

extension Plausible: PlausibleEventClient {}

class PlausibleAnalytics: NSObject {
    private let client: any PlausibleEventClient
    private var defaultProperties: [String: (any Sendable)?] = [:]

    init(defaultDomainURL: URL, analyticsServerURL: URL) {
        self.client = Plausible(defaultDomain: defaultDomainURL.host!, serverURL: analyticsServerURL)
    }

    /// Test / alternate-transport entry point. Prefer the URL-based init in production.
    init(client: any PlausibleEventClient) {
        self.client = client
    }

    /// Coerces an `@objc Analytics` `Any?` value into a Plausible-safe `Sendable` prop.
    ///
    /// String and `NSNumber` (Int/Double/Bool via the ObjC bridge) pass through typed so
    /// server-side prop filters keep working; everything else is stringified.
    static func sendablePropValue(from value: Any?) -> (any Sendable)? {
        switch value {
        case nil:
            return nil
        case let string as String:
            return string
        case let number as NSNumber:
            return number
        default:
            return value.map { String(describing: $0) }
        }
    }

    private func postEvent(pageURL: String, props: [String: (any Sendable)?]) async {
        let event = Event(url: pageURL, props: buildProps(props))
        do {
            try await client.postEvent(event)
        } catch let error {
            print("Error: \(error)")
        }
    }

    func reportEvent(pageURL: String, label: String, value: Any?) async {
        let sendableValue = Self.sendablePropValue(from: value)
        await postEvent(pageURL: pageURL, props: [label: sendableValue])
    }

    func reportSearchQuery(_ query: String) async {
        await reportEvent(pageURL: "app://localhost/search", label: "query", value: query)
    }

    func reportStopViewed(name: String, id: String, stopDistance: String) async {
        await postEvent(pageURL: "app://localhost/stop", props: ["id": id, "distance": stopDistance])
    }

    public func setUserProperty(key: String, value: String?) {
        defaultProperties[key] = value
    }

    private func buildProps(_ moreProps: [String: (any Sendable)?]) -> [String: (any Sendable)?] {
        defaultProperties.merging(moreProps) { _, new in new }
    }
}
