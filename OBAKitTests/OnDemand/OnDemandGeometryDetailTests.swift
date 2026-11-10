//
//  OnDemandGeometryDetailTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

/// Tests for `OnDemandGeometryDetail` API query string parameter values and cases.
@Suite(.serialized)
struct OnDemandGeometryDetailTests {

    @Test func `OnDemandGeometryDetail raw string values match API contract`() {
        #expect(OnDemandGeometryDetail.none.rawValue == "none")
        #expect(OnDemandGeometryDetail.simplified.rawValue == "simplified")
        #expect(OnDemandGeometryDetail.full.rawValue == "full")
    }

    @Test func `OnDemandGeometryDetail initializes correctly from valid strings`() {
        #expect(OnDemandGeometryDetail(rawValue: "none") == OnDemandGeometryDetail.none)
        #expect(OnDemandGeometryDetail(rawValue: "simplified") == OnDemandGeometryDetail.simplified)
        #expect(OnDemandGeometryDetail(rawValue: "full") == OnDemandGeometryDetail.full)
        #expect(OnDemandGeometryDetail(rawValue: "unknown") == nil)
        #expect(OnDemandGeometryDetail(rawValue: "") == nil)
    }
}
