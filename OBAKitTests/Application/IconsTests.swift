//
//  IconsTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import UIKit
import Testing
@testable import OBAKit

/// `Icons` force-unwraps `UIImage(systemName:)`, so a symbol name that doesn't
/// resolve on the running OS is a crash the first time the icon is drawn rather
/// than a build failure. These pin the departure-type pair.
@Suite
struct IconsTests {

    /// Asserts on the names rather than the rendered images: two `UIImage`s built
    /// from different symbols are not usefully comparable (symbol images carry no
    /// bitmap to diff, and identity says nothing), while the names are exactly the
    /// contract the two stop pages share.
    @Test func `Departure type symbol differs by state`() {
        #expect(Icons.departureTypeSymbolName(isActive: false) != Icons.departureTypeSymbolName(isActive: true))
    }

    @Test func `Departure type symbols resolve on this OS`() {
        // The names must resolve, or `departureType(isActive:)` traps on unwrap.
        #expect(UIImage(systemName: Icons.departureTypeSymbolName(isActive: false)) != nil)
        #expect(UIImage(systemName: Icons.departureTypeSymbolName(isActive: true)) != nil)

        // And the force-unwrapping accessor itself must survive both states.
        #expect(Icons.departureType(isActive: false).size != .zero)
        #expect(Icons.departureType(isActive: true).size != .zero)
    }
}
