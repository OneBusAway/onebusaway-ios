//
//  VehicleCalloutViewTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Testing
import UIKit
@testable import OBAKit
@testable import OBAKitCore

@MainActor
@Suite(.serialized)
final class VehicleCalloutViewTests {

    private func makeView(onFollow: @escaping () -> Void = {}) -> VehicleCalloutView {
        VehicleCalloutView(
            routeShortName: "H",
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

    /// The callout is a `detailCalloutAccessoryView`, which MapKit sizes from
    /// Auto Layout. Without a resolvable height the card collapses; without the
    /// pinned width it shrinks to the widest single word.
    @Test func `The callout resolves to a laid-out size`() {
        let view = makeView()
        let size = view.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)

        #expect(size.width == 240)
        #expect(size.height > 100)
    }

    /// The headsign wraps rather than truncating — the one deliberate departure
    /// from the design, since a headsign is the text a rider has to read.
    @Test func `A long headsign grows the callout instead of truncating`() {
        let short = makeView()
        let long = VehicleCalloutView(
            routeShortName: "H",
            headsign: "Capitol Hill Via 15th Ave E And Some More Words",
            vehicleLabel: "Vehicle 6821",
            countdownText: "1m",
            statusText: "1 min late",
            statusColor: .systemBlue,
            updatedText: "12s ago",
            routeColor: .systemRed,
            onFollow: {}
        )

        let shortHeight = short.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).height
        let longHeight = long.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).height

        #expect(longHeight > shortHeight)
    }

    /// MapKit drew `MKAnnotation.title` above the accessory view, which duplicated
    /// the vehicle line inside it. `StopVehicleAnnotation` suppresses it.
    @Test func `The vehicle annotation reports no title, so MapKit draws no title row`() throws {
        let status = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals_and_departures_for_stop_1_10020.json"
        ).arrivalsAndDepartures.compactMap(\.tripStatus).first
        let tripStatus = try #require(status)

        let annotation = StopVehicleAnnotation(
            id: "v1",
            routeID: "r1",
            routeColor: .systemRed,
            departureID: "d1",
            tripStatus: tripStatus,
            coordinate: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3)
        )

        #expect(tripStatus.title != nil) // the superclass would have used this
        #expect(annotation.title == nil)
    }

    @Test func `Distinct departures produce distinguishable callout content`() {
        // Not a proof by itself, but guards against the two constructor calls
        // silently producing identical output — the real distinguishing test
        // lives in StopRouteFocusMapLayerTests, which proves the layer re-reads
        // departureProvider rather than caching a stale ArrivalDeparture.
        let first = VehicleCalloutView(
            routeShortName: "H",
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
            routeShortName: "522",
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
