//
//  MapBaseTypeMapStyleTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
@testable import OBAKit

/// `MapStyle` is opaque and not `Equatable`, so the decision is modelled as a
/// descriptor that *is*, and the descriptor is what these tests assert. The
/// panel's `.mapStyle` modifier then reads `descriptor.mapStyle`.
@Suite(.serialized)
struct MapBaseTypeMapStyleTests {

    @Test func `Standard keeps the muted emphasis and honours points of interest`() {
        #expect(MapBaseType.standard.styleDescriptor(showingPointsOfInterest: true) == .standard(pointsOfInterest: true))
        #expect(MapBaseType.standard.styleDescriptor(showingPointsOfInterest: false) == .standard(pointsOfInterest: false))
    }

    /// The bug this task fixes: satellite used to fall through to hybrid,
    /// making the sheet's third basemap tile indistinguishable from its second.
    @Test func `Satellite maps to imagery, not hybrid`() {
        #expect(MapBaseType.satellite.styleDescriptor(showingPointsOfInterest: true) == .imagery)
        #expect(MapBaseType.satellite.styleDescriptor(showingPointsOfInterest: false) == .imagery)
    }

    @Test func `Hybrid honours points of interest`() {
        #expect(MapBaseType.hybrid.styleDescriptor(showingPointsOfInterest: true) == .hybrid(pointsOfInterest: true))
        #expect(MapBaseType.hybrid.styleDescriptor(showingPointsOfInterest: false) == .hybrid(pointsOfInterest: false))
    }

    /// Imagery carries no labels, so there is nothing for the POI preference to
    /// act on — the descriptor must not vary with it.
    @Test func `Imagery ignores the points of interest preference`() {
        let on = MapBaseType.satellite.styleDescriptor(showingPointsOfInterest: true)
        let off = MapBaseType.satellite.styleDescriptor(showingPointsOfInterest: false)
        #expect(on == off)
    }
}
