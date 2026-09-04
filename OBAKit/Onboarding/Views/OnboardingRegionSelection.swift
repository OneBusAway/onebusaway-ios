//
//  OnboardingRegionSelection.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import OBAKitCore

/// The region the onboarding card displays, paired with how the app arrived at it.
///
/// Both the card's eyebrow and the screen's body text are derived from `source`, so
/// they can't drift into describing the region two different ways.
/// See https://github.com/OneBusAway/onebusaway-ios/issues/1345
struct OnboardingRegionSelection {

    /// Where the displayed region came from.
    enum Source {
        /// The rider's location resolves to this region.
        case detected

        /// The rider tapped this region in the list on the onboarding screen.
        case chosen

        /// The app already had this region selected and the rider's location doesn't
        /// corroborate it — a fixed region from `OBAKitConfig`, the sole-active-region
        /// fallback, or a pick that predates this run of onboarding.
        case preselected
    }

    let region: Region
    let source: Source

    /// The region the rider's location resolves to: the one whose service area contains
    /// them, else the one with the closest center.
    ///
    /// Containment is checked first to match how `RegionsService` auto-selects a region.
    /// `distanceFrom(location:)` measures to a region's *center*, so a rider well inside a
    /// large region can still sit closer to a small neighbor's center; picking by distance
    /// alone would disagree with the region the app actually selected for them.
    ///
    /// - Returns: `nil` when there is no location, which is what distinguishes a genuinely
    ///   detected region from one that merely happens to be current.
    static func locatedRegion(in regions: [Region], location: CLLocation?) -> Region? {
        guard let location else { return nil }

        if let containing = regions.first(where: { $0.contains(location: location) }) {
            return containing
        }

        return regions.min { $0.distanceFrom(location: location) < $1.distanceFrom(location: location) }
    }

    /// Resolves which region the card shows and how it got there.
    ///
    /// - Parameters:
    ///   - chosen: The region the rider tapped on the onboarding screen, if any.
    ///   - current: `RegionProvider.currentRegion`.
    ///   - located: The result of ``locatedRegion(in:location:)``.
    /// - Returns: `nil` when there is nothing to show: no pick, no current region, no location.
    static func resolve(chosen: Region?, current: Region?, located: Region?) -> OnboardingRegionSelection? {
        if let chosen {
            return OnboardingRegionSelection(region: chosen, source: .chosen)
        }

        if let current {
            // `RegionsService` also assigns `currentRegion` from paths that have nothing to
            // do with the rider's location, so it only earns the "detected" label when the
            // location independently resolves to that same region.
            let source: Source = current.id == located?.id ? .detected : .preselected
            return OnboardingRegionSelection(region: current, source: source)
        }

        if let located {
            return OnboardingRegionSelection(region: located, source: .detected)
        }

        return nil
    }
}
