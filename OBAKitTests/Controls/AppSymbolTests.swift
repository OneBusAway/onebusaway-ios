//
//  AppSymbolTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
import UIKit
@testable import OBAKit

@MainActor
@Suite(.serialized)
struct AppSymbolTests {

    /// Verifies that all static symbol name constants are non-empty.
    @Test func testSymbolNamesAreNonEmpty() {
        #expect(!AppSymbol.error.isEmpty)
        #expect(!AppSymbol.loading.isEmpty)
        #expect(!AppSymbol.retry.isEmpty)
        #expect(!AppSymbol.refresh.isEmpty)
        #expect(!AppSymbol.search.isEmpty)
        #expect(!AppSymbol.locationUnavailable.isEmpty)
        #expect(!AppSymbol.locationFinding.isEmpty)
        #expect(!AppSymbol.bus.isEmpty)
        #expect(!AppSymbol.noRealtime.isEmpty)
    }

    /// Verifies that all AppSymbol strings resolve to valid, existing system SF Symbols in UIKit.
    @Test func testSymbolsExistInSystemCatalog() {
        let symbols = [
            AppSymbol.error,
            AppSymbol.loading,
            AppSymbol.retry,
            AppSymbol.refresh,
            AppSymbol.search,
            AppSymbol.locationUnavailable,
            AppSymbol.locationFinding,
            AppSymbol.bus,
            AppSymbol.noRealtime
        ]

        for symbol in symbols {
            let image = UIImage(systemName: symbol)
            #expect(image != nil, "Expected SF Symbol '\(symbol)' to exist in the system catalog")
        }
    }

    /// Verifies that canonical loading, retry, and refresh share the same system symbol name by design.
    @Test func testActionGlyphParity() {
        #expect(AppSymbol.loading == "arrow.clockwise")
        #expect(AppSymbol.retry == "arrow.clockwise")
        #expect(AppSymbol.refresh == "arrow.clockwise")
    }

    /// Verifies expected literal names for specific semantic transit and location roles.
    @Test func testSpecificRoleSymbolNames() {
        #expect(AppSymbol.error == "exclamationmark.triangle")
        #expect(AppSymbol.search == "magnifyingglass")
        #expect(AppSymbol.locationUnavailable == "location.slash")
        #expect(AppSymbol.locationFinding == "location.viewfinder")
        #expect(AppSymbol.bus == "bus")
        #expect(AppSymbol.noRealtime == "antenna.radiowaves.left.and.right.slash")
    }
}
