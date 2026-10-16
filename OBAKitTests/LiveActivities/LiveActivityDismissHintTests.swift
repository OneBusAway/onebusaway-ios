//
//  LiveActivityDismissHintTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import SwiftUI
import Testing
import UIKit
@testable import OBAKitCore

/// Riders' first Live Activity says how to get rid of it: swipe it away on the
/// Lock Screen (#1553). Later ones don't.
@MainActor
@Suite(.serialized)
final class LiveActivityDismissHintTests {

    private let suiteName = "LiveActivityDismissHintTests-\(UUID().uuidString)"
    private let userDefaults: UserDefaults

    init() throws {
        userDefaults = try #require(UserDefaults(suiteName: suiteName))
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    private let staticData = TripAttributes.StaticData(
        routeShortName: "60",
        routeHeadsign: "Broadway First Hill",
        stopID: "1_39990",
        regionID: 1,
        tripID: "trip_1"
    )

    // MARK: - Once only

    @Test func `The first Live Activity shows the hint and later ones don't`() {
        let hint = LiveActivityDismissHint(userDefaults: userDefaults)

        #expect(hint.isPending)
        // Asking doesn't spend it: a request that then fails leaves it for the next.
        #expect(hint.isPending)

        hint.markShown()
        #expect(!hint.isPending)
        // The flag lives in defaults, not the instance: a fresh one agrees.
        #expect(!LiveActivityDismissHint(userDefaults: userDefaults).isPending)
    }

    // MARK: - Wire format

    /// Activities already running, and push payloads built before this field
    /// existed, carry no `showsDismissHint`. They must still decode.
    @Test func `Attributes without the field decode, and show no hint`() throws {
        let legacy = try JSONEncoder().encode(LegacyTripAttributes(staticData: staticData))
        let decoded = try JSONDecoder().decode(TripAttributes.self, from: legacy)

        #expect(!decoded.showsDismissHint)
        #expect(decoded.staticData == staticData)
    }

    @Test func `The field round-trips`() throws {
        let attributes = TripAttributes(staticData: staticData, showsDismissHint: true)
        let decoded = try JSONDecoder().decode(TripAttributes.self, from: JSONEncoder().encode(attributes))

        #expect(decoded.showsDismissHint)
    }

    // MARK: - The card

    /// The hint is one extra line under the arrivals, so the card grows by it.
    @Test func `The Lock Screen card draws the hint only when asked`() {
        let state = TripAttributes.ContentState(arrivals: [
            .init(departureTime: Int(Date().timeIntervalSince1970) + 600, scheduleStatus: .onTime, scheduleDeviation: 0, isArrival: false)
        ])
        func height(showsDismissHint: Bool) -> CGFloat {
            let card = TripLiveActivityCardView(staticData: staticData, contentState: state, showsDismissHint: showsDismissHint)
            return UIHostingController(rootView: card).sizeThatFits(in: CGSize(width: 370, height: 1000)).height
        }

        #expect(height(showsDismissHint: true) > height(showsDismissHint: false))
    }

    /// ActivityKit clips a Lock Screen card past 160 pt. A stale card already adds a
    /// warning row, which matters more than the hint, so the hint steps aside.
    @Test func `A stale card drops the hint and stays within the Lock Screen's height`() {
        let now = Int(Date().timeIntervalSince1970)
        let state = TripAttributes.ContentState(arrivals: [600, 1500, 2400].map {
            .init(departureTime: now + $0, scheduleStatus: .onTime, scheduleDeviation: 0, isArrival: false)
        })
        func height(showsDismissHint: Bool) -> CGFloat {
            let card = TripLiveActivityCardView(staticData: staticData, contentState: state, isStale: true, showsDismissHint: showsDismissHint)
            return UIHostingController(rootView: card).sizeThatFits(in: CGSize(width: 370, height: 1000)).height
        }

        #expect(height(showsDismissHint: true) == height(showsDismissHint: false))
        #expect(height(showsDismissHint: true) <= 160)
    }
}

/// `TripAttributes` as encoded before `showsDismissHint` existed.
private struct LegacyTripAttributes: Encodable {
    let staticData: TripAttributes.StaticData
}
