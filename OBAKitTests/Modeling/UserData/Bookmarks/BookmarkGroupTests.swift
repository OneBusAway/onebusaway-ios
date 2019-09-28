//
//  BookmarkGroupTests.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 6/22/19.
//

import XCTest
import Nimble
import OHHTTPStubs
import CoreLocation
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_try

class BookmarkGroupTests: OBATestCase {

    func testCreation() {
        let group = BookmarkGroup(name: "Group 1")
        expect(group.name) == "Group 1"
        expect(group.uuid).toNot(beNil())
    }

    func testCodableRoundtripping() {
        let group = BookmarkGroup(name: "Group 1")
        let encoded = try! PropertyListEncoder().encode(group)
        let decoded = try! PropertyListDecoder().decode(BookmarkGroup.self, from: encoded)

        expect(decoded.name) == "Group 1"
        expect(decoded.uuid).toNot(beNil())
        expect(decoded.uuid) == group.uuid
    }
}
