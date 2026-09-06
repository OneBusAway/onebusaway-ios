//
//  OnboardingRegionSelectionTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import MapKit
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// Tests for `OnboardingRegionSelection`, which decides which region the onboarding
/// card shows and whether the app may claim it detected that region.
/// See https://github.com/OneBusAway/onebusaway-ios/issues/1345
@MainActor
@Suite(.serialized)
final class OnboardingRegionSelectionTests {

    private func makeRegion(id: RegionIdentifier, name: String, latitude: CLLocationDegrees, longitude: CLLocationDegrees, span: CLLocationDegrees) -> Region {
        Region(
            name: name,
            OBABaseURL: URL(string: "https://www.example.com")!,
            coordinateRegion: MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)),
            contactEmail: "contact@example.com",
            regionIdentifier: id)
    }

    /// Spans latitude 45...49, longitude -124...-120.
    private var pugetSound: Region {
        makeRegion(id: 1, name: "Puget Sound", latitude: 47.0, longitude: -122.0, span: 4.0)
    }

    /// A pinprick region just north of `riderInPugetSound`, so its center is far closer
    /// than Puget Sound's while its bounds exclude the rider.
    private var smallNeighbor: Region {
        makeRegion(id: 2, name: "Small Neighbor", latitude: 47.62, longitude: -122.30, span: 0.01)
    }

    private var tampaBay: Region {
        makeRegion(id: 3, name: "Tampa Bay", latitude: 27.98, longitude: -82.45, span: 0.5)
    }

    private let riderInPugetSound = CLLocation(latitude: 47.60, longitude: -122.32)

    /// Outside every test region, and roughly 270km from Tampa Bay's center versus
    /// thousands of kilometers from Puget Sound's.
    private let riderInNorthFlorida = CLLocation(latitude: 30.0, longitude: -84.0)

    // MARK: - locatedRegion

    @Test func `Located region is nil without a location`() {
        #expect(OnboardingRegionSelection.locatedRegion(in: [pugetSound, tampaBay], location: nil) == nil)
    }

    @Test func `Located region is nil when no regions are known`() {
        #expect(OnboardingRegionSelection.locatedRegion(in: [], location: riderInPugetSound) == nil)
    }

    /// `distanceFrom(location:)` measures to a region's center, so a rider well inside a
    /// large region can sit closer to a small neighbor's center. Containment has to win,
    /// or the label disagrees with the region `RegionsService` actually auto-selects.
    @Test func `Located region prefers the containing region over a closer center`() throws {
        let neighbor = smallNeighbor
        let containing = pugetSound

        // Guard the fixture itself: the test is meaningless if the neighbor isn't closer.
        #expect(neighbor.distanceFrom(location: riderInPugetSound) < containing.distanceFrom(location: riderInPugetSound))
        #expect(neighbor.contains(location: riderInPugetSound) == false)

        // Neighbor first, so the containing region can't win by array order alone.
        let located = try #require(OnboardingRegionSelection.locatedRegion(in: [neighbor, containing], location: riderInPugetSound))
        #expect(located.regionIdentifier == 1)
    }

    @Test func `Located region falls back to the nearest center when none contains the rider`() throws {
        let regions = [pugetSound, tampaBay]
        #expect(regions.contains { $0.contains(location: riderInNorthFlorida) } == false)

        let located = try #require(OnboardingRegionSelection.locatedRegion(in: regions, location: riderInNorthFlorida))
        #expect(located.regionIdentifier == 3)
    }

    // MARK: - resolve

    @Test func `Resolve reports a rider tap as chosen`() throws {
        let selection = try #require(OnboardingRegionSelection.resolve(chosen: tampaBay, current: pugetSound, located: pugetSound))
        #expect(selection.source == .chosen)
        #expect(selection.region.regionIdentifier == 3)
    }

    @Test func `Resolve reports a location-corroborated current region as detected`() throws {
        let selection = try #require(OnboardingRegionSelection.resolve(chosen: nil, current: pugetSound, located: pugetSound))
        #expect(selection.source == .detected)
        #expect(selection.region.regionIdentifier == 1)
    }

    /// The bug behind #1345: `RegionsService` also sets `currentRegion` from a fixed region
    /// name and from the sole-active-region fallback, neither of which involves the rider's
    /// location. Those must not be labelled "Detected near you".
    @Test func `Resolve reports a current region the location contradicts as preselected`() throws {
        let selection = try #require(OnboardingRegionSelection.resolve(chosen: nil, current: tampaBay, located: pugetSound))
        #expect(selection.source == .preselected)
        #expect(selection.region.regionIdentifier == 3)
    }

    @Test func `Resolve reports a current region as preselected when there is no location`() throws {
        let selection = try #require(OnboardingRegionSelection.resolve(chosen: nil, current: tampaBay, located: nil))
        #expect(selection.source == .preselected)
        #expect(selection.region.regionIdentifier == 3)
    }

    @Test func `Resolve reports a located region as detected when nothing is current`() throws {
        let selection = try #require(OnboardingRegionSelection.resolve(chosen: nil, current: nil, located: pugetSound))
        #expect(selection.source == .detected)
        #expect(selection.region.regionIdentifier == 1)
    }

    @Test func `Resolve returns nil without a tap a current region or a location`() {
        #expect(OnboardingRegionSelection.resolve(chosen: nil, current: nil, located: nil) == nil)
    }
}
