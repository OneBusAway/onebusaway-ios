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
    /// from the design, since a headsign is the one piece of text here a rider has to read.
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

    @Test func `Standard content size maintains horizontal header and 32pt badge`() {
        let view = makeView()
        view.updateLayout(for: UITraitCollection(preferredContentSizeCategory: .large))

        #expect(view.headerStackAxis == .horizontal)
        #expect(view.badgeSize == 32)
        let size = view.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        #expect(size.width == 240)
        #expect(size.height > 100)
    }

    @Test func `Accessibility content size adapts header stack to vertical, scales badge, and grows callout downward`() {
        let view = makeView()
        view.updateLayout(for: UITraitCollection(preferredContentSizeCategory: .large))
        let standardSize = view.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)

        let accessibilityTraits = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraLarge)
        view.updateLayout(for: accessibilityTraits)

        #expect(view.headerStackAxis == .vertical)
        #expect(view.badgeSize > 32)
        #expect(view.badgeLabel.font.pointSize > 17)

        let a11ySize = view.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        // Width remains bounded to 240pt so callout does not overflow screen width
        #expect(a11ySize.width == 240)
        // Vertical header and wrapping text expand callout downward
        #expect(a11ySize.height > standardSize.height)
    }

    @Test func `Dynamic Type size category changes dynamically switch header axis and badge scale`() {
        let view = makeView()

        // Switch to accessibility size
        view.updateLayout(for: UITraitCollection(preferredContentSizeCategory: .accessibilityMedium))
        #expect(view.headerStackAxis == .vertical)
        #expect(view.badgeSize > 32)

        // Switch back to standard default size (.large)
        view.updateLayout(for: UITraitCollection(preferredContentSizeCategory: .large))
        #expect(view.headerStackAxis == .horizontal)
        #expect(view.badgeSize == 32)

        // Switch to smaller size (.medium scales below standard)
        view.updateLayout(for: UITraitCollection(preferredContentSizeCategory: .medium))
        #expect(view.headerStackAxis == .horizontal)
        #expect(view.badgeSize < 32)
    }

    @Test func `Long headsign wraps without clipping at both standard and accessibility sizes`() {
        let longHeadsign = "Very Long Headsign That Spans Multiple Lines Via Downtown Seattle University District And Northgate Transit Center"
        let view = VehicleCalloutView(
            routeShortName: "H",
            headsign: longHeadsign,
            vehicleLabel: "Vehicle 6821",
            countdownText: "1m",
            statusText: "1 min late",
            statusColor: .systemBlue,
            updatedText: "12s ago",
            routeColor: .systemRed,
            onFollow: {}
        )

        #expect(view.headsignLabel.numberOfLines == 0)

        // Standard size: grows callout vertically
        view.updateLayout(for: UITraitCollection(preferredContentSizeCategory: .large))
        let standardHeight = view.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).height
        #expect(standardHeight > 100)

        // Accessibility size: adapts to vertical header and grows even taller without clipping
        view.updateLayout(for: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraLarge))
        let accessibilityHeight = view.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).height
        #expect(accessibilityHeight > standardHeight)
    }

    @Test func `Callout accommodates compact widths and wraps text properly`() {
        let view = makeView()
        view.updateLayout(for: UITraitCollection(preferredContentSizeCategory: .large))

        // Compress horizontally to 200pt (smaller than standard 240pt width)
        let compactWidth: CGFloat = 200
        let compactSize = view.systemLayoutSizeFitting(
            CGSize(width: compactWidth, height: UIView.noIntrinsicMetric),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )

        #expect(compactSize.width == compactWidth)
        #expect(compactSize.height > 100)

        // Even in compact width with accessibility category
        view.updateLayout(for: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraLarge))
        let compactA11ySize = view.systemLayoutSizeFitting(
            CGSize(width: compactWidth, height: UIView.noIntrinsicMetric),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        #expect(compactA11ySize.width == compactWidth)
        #expect(compactA11ySize.height > compactSize.height)
    }

    @Test func `Callout adapts properly to right-to-left layout direction`() {
        let view = makeView()
        let rtlTraits = UITraitCollection(layoutDirection: .rightToLeft)
        view.updateLayout(for: rtlTraits)

        view.frame = CGRect(x: 0, y: 0, width: 240, height: 200)
        view.setNeedsLayout()
        view.layoutIfNeeded()

        // Follow button chevron trailing edge placed properly in RTL
        #expect(view.followButton.configuration?.imagePlacement == .trailing)
    }
}
