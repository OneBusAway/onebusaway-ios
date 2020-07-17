//
//  BookmarkGroupTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
import CoreLocation
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_try

class BookmarkGroupTests: OBATestCase {

    func testCreation() {
        let group = BookmarkGroup(name: "Group 1", sortOrder: 0)
        expect(group.name) == "Group 1"
        expect(group.id).toNot(beNil())
    }

    func testCodableRoundtripping() {
        let group = BookmarkGroup(name: "Group 1", sortOrder: 10)
        let decoded = try! Fixtures.roundtripCodable(type: BookmarkGroup.self, model: group)

        expect(decoded.name) == "Group 1"
        expect(decoded.id).toNot(beNil())
        expect(decoded.id) == group.id
        expect(decoded.sortOrder) == 10
    }
}
