//
//  MapKitExtensionTest.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 12/15/19.
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
        let decoded = try! roundtripCodable(type: MKMapRect.self, model: TestData.seattleMapRect)
        expect(decoded.origin.x) == TestData.seattleMapRect.origin.x
        expect(decoded.origin.y) == TestData.seattleMapRect.origin.y
        expect(decoded.size.width) == TestData.seattleMapRect.size.width
        expect(decoded.size.height) == TestData.seattleMapRect.size.height
    }
}
