//
//  StopTripSpacingTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
@testable import OBAKit

@Suite(.serialized)
struct StopTripSpacingTests {

    /// Regular numbers are the layout the new stop/trip screens shipped with.
    /// Change a call site off `StopTripSpacing` and these stay green — they pin
    /// the table the views are required to call, not SwiftUI itself.
    @Test func `Regular spacing matches the shipped stop and trip layout`() {
        #expect(StopTripSpacing.stack(false) == 3)
        #expect(StopTripSpacing.hStack(false) == 13)
        #expect(StopTripSpacing.card(false) == 10)
        #expect(StopTripSpacing.tripPage(false) == 14)
        #expect(StopTripSpacing.stopRowVertical(false) == 11)
        #expect(StopTripSpacing.cardPadding(false) == 14)
    }

    /// Compact is strictly tighter on every axis the mode is allowed to touch.
    /// Restoring compact == regular fails this.
    @Test func `Compact spacing is tighter than regular`() {
        #expect(StopTripSpacing.stack(true) == 1)
        #expect(StopTripSpacing.hStack(true) == 8)
        #expect(StopTripSpacing.card(true) == 6)
        #expect(StopTripSpacing.tripPage(true) == 8)
        #expect(StopTripSpacing.stopRowVertical(true) == 6)
        #expect(StopTripSpacing.cardPadding(true) == 10)

        #expect(StopTripSpacing.stack(true) < StopTripSpacing.stack(false))
        #expect(StopTripSpacing.hStack(true) < StopTripSpacing.hStack(false))
        #expect(StopTripSpacing.card(true) < StopTripSpacing.card(false))
        #expect(StopTripSpacing.tripPage(true) < StopTripSpacing.tripPage(false))
        #expect(StopTripSpacing.stopRowVertical(true) < StopTripSpacing.stopRowVertical(false))
        #expect(StopTripSpacing.cardPadding(true) < StopTripSpacing.cardPadding(false))
    }

    /// Compact padding would otherwise drop a tappable trip-stop row under
    /// 44pt. Drop this constant and the Accessibility setting shrinks the
    /// hit target — the thing Aaron blocked #1297 on.
    @Test func `Tappable trip-stop rows keep a 44pt minimum height`() {
        #expect(StopTripSpacing.stopRowMinHeight == 44)
        #expect(StopTripSpacing.stopRowMinHeight > StopTripSpacing.stopRowVertical(true) * 2)
    }
}
