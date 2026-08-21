//
//  StopSheetTitleFadeTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreGraphics
import Testing
@testable import OBAKit

/// The pinned title's fade arithmetic. Extracted from the view because it is
/// the part most likely to misbehave and the only part a unit test can reach —
/// the scroll interaction itself needs a real scroll view.
@Suite(.serialized)
struct StopSheetTitleFadeTests {

    @Test func `At rest the title is fully faded out`() {
        #expect(StopSheetTitleFade.progress(scrollOffset: 0, fadeDistance: 170) == 0)
    }

    @Test func `Scrolling the full fade distance fully fades in`() {
        #expect(StopSheetTitleFade.progress(scrollOffset: 170, fadeDistance: 170) == 1)
    }

    @Test func `Halfway through the range is half faded`() {
        #expect(StopSheetTitleFade.progress(scrollOffset: 85, fadeDistance: 170) == 0.5)
    }

    @Test func `Overscrolling past a full fade clamps to one`() {
        #expect(StopSheetTitleFade.progress(scrollOffset: 900, fadeDistance: 170) == 1)
    }

    @Test func `Rubber banding above the top clamps to zero`() {
        #expect(StopSheetTitleFade.progress(scrollOffset: -120, fadeDistance: 170) == 0)
    }

    /// A stop that never resolves has no header to scroll past. Without this
    /// guard the range divides by zero.
    @Test func `A zero fade distance reports no progress`() {
        #expect(StopSheetTitleFade.progress(scrollOffset: 50, fadeDistance: 0) == 0)
    }

    @Test func `A negative fade distance reports no progress`() {
        #expect(StopSheetTitleFade.progress(scrollOffset: 50, fadeDistance: -10) == 0)
    }

    @Test func `Progress is monotonic across the range`() {
        var previous: CGFloat = -1
        for offset in stride(from: CGFloat(0), through: 170, by: 10) {
            let value = StopSheetTitleFade.progress(scrollOffset: offset, fadeDistance: 170)
            #expect(value >= previous)
            previous = value
        }
    }
}
