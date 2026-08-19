//
//  StopPageSheetHeaderCloseButtonTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
import OBAKitCore
@testable import OBAKit

/// Who owns the close button.
///
/// The header carries one because the pushed sheet presentation has no
/// navigation bar behind it. The map sheet's own top bar carries one too, so
/// there the header's must be suppressed or the rider sees two ✕ a few points
/// apart. The default is what keeps the pushed presentation's only way out from
/// disappearing if someone flips it.
@MainActor
@Suite(.serialized)
struct StopPageSheetHeaderCloseButtonTests {

    /// `Fixtures.loadSomeStops()` is the project's only `Stop` source and it
    /// throws — the same call `StopPageSheetHeaderLayoutTests` uses.
    private func someStop() throws -> Stop {
        try #require(Fixtures.loadSomeStops().first)
    }

    @Test func `The header shows its close button by default`() throws {
        let header = StopPageSheetHeaderView(
            stop: try someStop(),
            walkTime: nil,
            onWalkingDirections: {},
            onClose: {},
            mapFocus: StopMapFocus()
        )
        #expect(header.showsCloseButton)
    }

    @Test func `The header can suppress its close button`() throws {
        let header = StopPageSheetHeaderView(
            stop: try someStop(),
            walkTime: nil,
            onWalkingDirections: {},
            onClose: {},
            showsCloseButton: false,
            mapFocus: StopMapFocus()
        )
        #expect(!header.showsCloseButton)
    }

    @Test func `The placeholder shows its close button by default`() {
        let placeholder = StopPageSheetHeaderPlaceholderView(onClose: {})
        #expect(placeholder.showsCloseButton)
    }

    @Test func `The placeholder can suppress its close button`() {
        let placeholder = StopPageSheetHeaderPlaceholderView(onClose: {}, showsCloseButton: false)
        #expect(!placeholder.showsCloseButton)
    }
}
