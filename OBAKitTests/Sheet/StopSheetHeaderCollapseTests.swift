//
//  StopSheetHeaderCollapseTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreGraphics
import Testing
@testable import OBAKit

/// The collapsing header's arithmetic. Extracted from the view because it is
/// the part most likely to misbehave and the only part a unit test can reach —
/// the scroll interaction itself needs a real scroll view.
@Suite(.serialized)
struct StopSheetHeaderCollapseTests {

    @Test func `At rest the header is fully expanded`() {
        #expect(StopSheetHeaderCollapse.progress(scrollOffset: 0, collapsibleHeight: 170) == 0)
    }

    @Test func `Scrolling the full collapsible height fully collapses`() {
        #expect(StopSheetHeaderCollapse.progress(scrollOffset: 170, collapsibleHeight: 170) == 1)
    }

    @Test func `Halfway through the range is half collapsed`() {
        #expect(StopSheetHeaderCollapse.progress(scrollOffset: 85, collapsibleHeight: 170) == 0.5)
    }

    @Test func `Overscrolling past full collapse clamps to one`() {
        #expect(StopSheetHeaderCollapse.progress(scrollOffset: 900, collapsibleHeight: 170) == 1)
    }

    @Test func `Rubber banding above the top clamps to zero`() {
        #expect(StopSheetHeaderCollapse.progress(scrollOffset: -120, collapsibleHeight: 170) == 0)
    }

    /// A stop that never resolves has no header to collapse. Without this
    /// guard the range divides by zero.
    @Test func `A zero collapsible height reports no progress`() {
        #expect(StopSheetHeaderCollapse.progress(scrollOffset: 50, collapsibleHeight: 0) == 0)
    }

    @Test func `A negative collapsible height reports no progress`() {
        #expect(StopSheetHeaderCollapse.progress(scrollOffset: 50, collapsibleHeight: -10) == 0)
    }

    @Test func `Progress is monotonic across the range`() {
        var previous: CGFloat = -1
        for offset in stride(from: CGFloat(0), through: 170, by: 10) {
            let value = StopSheetHeaderCollapse.progress(scrollOffset: offset, collapsibleHeight: 170)
            #expect(value >= previous)
            previous = value
        }
    }
}
