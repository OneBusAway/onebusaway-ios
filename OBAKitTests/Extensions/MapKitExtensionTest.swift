//
//  MapKitExtensionTest.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MapKit
import Nimble
import XCTest
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_try

class MapKitExtensionTest: OBATestCase {
    func testMapRectCodable_roundTripping() {
        let decoded = try! Fixtures.roundtripCodable(type: MKMapRect.self, model: TestData.seattleMapRect)
        expect(decoded.origin.x) == TestData.seattleMapRect.origin.x
        expect(decoded.origin.y) == TestData.seattleMapRect.origin.y
        expect(decoded.size.width) == TestData.seattleMapRect.size.width
        expect(decoded.size.height) == TestData.seattleMapRect.size.height
    }
}
