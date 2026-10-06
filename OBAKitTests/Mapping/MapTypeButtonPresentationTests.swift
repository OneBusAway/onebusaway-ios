//
//  MapTypeButtonPresentationTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import UIKit
@testable import OBAKit
@testable import OBAKitCore

/// The basemap button in the UIKit map's hover bar said "Map type" for a button
/// that opens the whole Map sheet, called satellite "hybrid", and never voiced
/// the layer badge. It now shares this presentation with the SwiftUI button.
@MainActor
@Suite(.serialized)
struct MapTypeButtonPresentationTests {

    @Test func `The label names the Map settings sheet the button opens`() {
        #expect(MapTypeButtonPresentation.accessibilityLabel == "Map settings")
    }

    @Test func `Each basemap has its own icon`() {
        let symbols = MapBaseType.allCases.map(MapTypeButtonPresentation.symbolName(for:))
        #expect(Set(symbols).count == MapBaseType.allCases.count)
    }

    @Test func `Satellite is announced as satellite, not hybrid`() {
        #expect(MapTypeButtonPresentation.accessibilityValue(mapType: .satellite, layerCount: 0) == "satellite")
        #expect(MapTypeButtonPresentation.accessibilityValue(mapType: .hybrid, layerCount: 0) == "hybrid")
        #expect(MapTypeButtonPresentation.accessibilityValue(mapType: .standard, layerCount: 0) == "standard")
    }

    @Test func `The value carries the layer count the badge shows`() {
        #expect(MapTypeButtonPresentation.accessibilityValue(mapType: .standard, layerCount: 1) == "standard, 1 layer on")
        #expect(MapTypeButtonPresentation.accessibilityValue(mapType: .satellite, layerCount: 3) == "satellite, 3 layers on")
    }

    @Test func `The badge digit clears 4.5 to 1 against the brand color`() {
        let brand = ThemeColors.shared.brand
        #expect(MapTypeButtonPresentation.badgeTextColor.wcagContrastRatio(against: brand) >= 4.5)
    }
}
