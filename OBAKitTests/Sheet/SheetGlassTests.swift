//
//  SheetGlassTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import Testing
@testable import OBAKit

/// Over the dark map, a partial-height sheet's glass washes out to a pale
/// blue-grey that white text can't be read against, so the map panel's sheets
/// show it in light mode only.
@Suite(.serialized)
struct SheetGlassTests {
    @Test
    func `Sheets show their glass in light mode on iOS 26`() {
        if #available(iOS 26.0, *) {
            #expect(ColorScheme.light.showsSheetGlass)
        } else {
            #expect(!ColorScheme.light.showsSheetGlass)
        }
    }

    @Test
    func `Sheets stay opaque in dark mode`() {
        #expect(!ColorScheme.dark.showsSheetGlass)
    }
}
