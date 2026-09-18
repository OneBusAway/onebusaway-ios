//
//  ThemeTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore
import UIKit

@Suite(.serialized)
final class ThemeTests {
    
    @Test func `ThemeMetrics constants are correct`() {
        #expect(ThemeMetrics.accessibilityPadding == 16.0)
        #expect(ThemeMetrics.padding == 8.0)
        #expect(ThemeMetrics.compactPadding == 4.0)
        #expect(ThemeMetrics.ultraCompactPadding == 2.0)
        #expect(ThemeMetrics.cornerRadius == 8.0)
        #expect(ThemeMetrics.compactCornerRadius == 4.0)
    }

    @Test func `ThemeColors initializes successfully`() {
        let colors = ThemeColors.shared
        #expect(colors.brand != nil)
        #expect(colors.errorColor == .systemRed)
        #expect(colors.departureEarly == .systemRed)
        #expect(colors.departureLate == .systemBlue)
        #expect(colors.departureUnknown == .label)
    }
}