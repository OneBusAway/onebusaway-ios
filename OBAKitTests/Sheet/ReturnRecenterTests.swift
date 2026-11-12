//
//  ReturnRecenterTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// The UIKit map re-centers on a rider who comes back after ten minutes away.
/// The panel stayed wherever it was left.
@Suite
struct ReturnRecenterTests {

    private var pugetSound: Region { Fixtures.pugetSoundRegion }

    @Test func `Ten minutes away in the region re-centers on the rider`() {
        #expect(ReturnRecenter.shouldRecenter(absence: 601, region: pugetSound, location: TestData.mockSeattleLocation, isShowingSheet: false))
    }

    @Test func `A short absence, an open sheet, no fix, or another city leaves the map`() {
        #expect(!ReturnRecenter.shouldRecenter(absence: 60, region: pugetSound, location: TestData.mockSeattleLocation, isShowingSheet: false))
        #expect(!ReturnRecenter.shouldRecenter(absence: 601, region: pugetSound, location: TestData.mockSeattleLocation, isShowingSheet: true))
        #expect(!ReturnRecenter.shouldRecenter(absence: 601, region: pugetSound, location: nil, isShowingSheet: false))
        #expect(!ReturnRecenter.shouldRecenter(absence: 601, region: pugetSound, location: TestData.mockTampaLocation, isShowingSheet: false))
    }
}
