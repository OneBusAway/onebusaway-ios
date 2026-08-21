//
//  ScrollToTopVisibilityTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreGraphics
import Testing
@testable import OBAKit

/// The scroll-to-top button's visibility rule. Extracted from the view because
/// it is the only part of the feature a unit test can reach — whether the
/// overlay actually renders, and whether tapping scrolls, both need a real
/// scroll view.
@Suite(.serialized)
struct ScrollToTopVisibilityTests {

    private let viewport: CGFloat = 800

    @Test func `Hidden at rest`() {
        #expect(!ScrollToTopVisibility.shouldShow(scrollOffset: 0, viewportHeight: viewport))
    }

    @Test func `Hidden just short of one viewport`() {
        #expect(!ScrollToTopVisibility.shouldShow(scrollOffset: 799, viewportHeight: viewport))
    }

    @Test func `Hidden at exactly one viewport`() {
        #expect(!ScrollToTopVisibility.shouldShow(scrollOffset: 800, viewportHeight: viewport))
    }

    @Test func `Shown just past one viewport`() {
        #expect(ScrollToTopVisibility.shouldShow(scrollOffset: 801, viewportHeight: viewport))
    }

    @Test func `Shown far down a long list`() {
        #expect(ScrollToTopVisibility.shouldShow(scrollOffset: 5000, viewportHeight: viewport))
    }

    /// Rubber-banding past the top yields a negative offset.
    @Test func `Hidden while rubber banding above the top`() {
        #expect(!ScrollToTopVisibility.shouldShow(scrollOffset: -120, viewportHeight: viewport))
    }

    /// Before the first layout pass the container has no height. Without the
    /// guard every offset counts as "more than nothing" and the button would
    /// appear on a sheet that has not been laid out.
    @Test func `Hidden before the sheet has been laid out`() {
        #expect(!ScrollToTopVisibility.shouldShow(scrollOffset: 500, viewportHeight: 0))
    }

    @Test func `Hidden for a negative viewport height`() {
        #expect(!ScrollToTopVisibility.shouldShow(scrollOffset: 500, viewportHeight: -10))
    }
}
