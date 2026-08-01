//
//  VehicleCalloutViewTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
import UIKit
import OBAKitCore
@testable import OBAKit

@MainActor
@Suite(.serialized)
final class VehicleCalloutViewTests {

    private func makeView(onFollow: @escaping () -> Void = {}) -> VehicleCalloutView {
        VehicleCalloutView(
            headsign: "Downtown Seattle",
            vehicleLabel: "Vehicle 6821",
            countdownText: "1m",
            statusText: "1 min late",
            statusColor: .systemBlue,
            updatedText: "position updated 12s ago",
            routeColor: .systemRed,
            onFollow: onFollow
        )
    }

    @Test func `Follow invokes the callback exactly once`() {
        var followCount = 0
        let view = makeView(onFollow: { followCount += 1 })

        view.simulateFollowTap()

        #expect(followCount == 1)
    }

    @Test func `The callout is a single VoiceOver element with the button trait`() {
        let view = makeView()

        // A callout stuffed with five separate labels is a worse VoiceOver
        // experience than one sentence read as a single button. If this ever
        // regresses to per-label accessibility elements, VoiceOver users get a
        // pile of unlabeled fragments instead of "Downtown Seattle, ... Button".
        #expect(view.isAccessibilityElement == true)
        #expect(view.accessibilityTraits.contains(.button))
    }

    @Test func `Activating the callout via VoiceOver triggers follow, independent of the button tap path`() {
        // This exercises accessibilityActivate() directly rather than
        // simulateFollowTap() — a VoiceOver "double tap to activate" gesture on a
        // single accessibility element does not send a UIControl touch event to
        // the button buried inside it. If accessibilityActivate() ever stopped
        // forwarding to onFollow (e.g. only the button's target-action fired),
        // this test would catch it while `simulateFollowTap` would not.
        var followCount = 0
        let view = makeView(onFollow: { followCount += 1 })

        let handled = view.accessibilityActivate()

        #expect(handled == true)
        #expect(followCount == 1)
    }

    @Test func `Distinct departures produce distinguishable callout content`() {
        // Not a proof by itself, but guards against the two constructor calls
        // silently producing identical output — the real distinguishing test
        // lives in StopRouteFocusMapLayerTests, which proves the layer re-reads
        // departureProvider rather than caching a stale ArrivalDeparture.
        let first = VehicleCalloutView(
            headsign: "Downtown Seattle",
            vehicleLabel: "Vehicle 1",
            countdownText: "1m",
            statusText: "1 min late",
            statusColor: .systemBlue,
            updatedText: "position updated 12s ago",
            routeColor: .systemRed,
            onFollow: {}
        )
        let second = VehicleCalloutView(
            headsign: "Lake City",
            vehicleLabel: "Vehicle 2",
            countdownText: "9m",
            statusText: "on time",
            statusColor: .systemGreen,
            updatedText: "position updated 40s ago",
            routeColor: .systemBlue,
            onFollow: {}
        )

        #expect(first.accessibilityLabel != second.accessibilityLabel)
        #expect(second.accessibilityLabel?.contains("Lake City") == true)
        #expect(second.accessibilityLabel?.contains("on time") == true)
    }
}
