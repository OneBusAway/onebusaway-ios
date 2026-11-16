//
//  StopCollapsedDetentTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
import CoreGraphics
@testable import OBAKit

/// The stop sheet's collapsed detent (#1751): the pinned top bar (actions and
/// Close) plus the stop's name block, measured, and never shorter than iOS 26
/// will draw a floating sheet.
@Suite(.serialized)
struct StopCollapsedDetentTests {

    @Test func `Collapsed holds the top bar and the name block`() {
        let height = StopCollapsedDetent.collapsedHeight(topBarHeight: 56, titleBlockHeight: 70)
        #expect(height == 126)
    }

    @Test func `Collapsed is never shorter than the floating sheet floor`() {
        let height = StopCollapsedDetent.collapsedHeight(topBarHeight: 40, titleBlockHeight: 20)
        #expect(height == StopCollapsedDetent.minimumHeight)
        #expect(StopCollapsedDetent.minimumHeight >= 100)
    }

    /// At accessibility sizes the name block grows; the detent grows with it
    /// instead of clipping the name and Close.
    @Test func `Collapsed grows with large text`() {
        let height = StopCollapsedDetent.collapsedHeight(topBarHeight: 80, titleBlockHeight: 220)
        #expect(height == 300)
    }

    /// Before the sheet has been laid out, an estimate stands in.
    @Test func `An unmeasured sheet uses the estimate`() {
        #expect(StopCollapsedDetent.collapsedHeight(topBarHeight: nil, titleBlockHeight: nil) == StopCollapsedDetent.estimatedHeight)
        #expect(StopCollapsedDetent.collapsedHeight(topBarHeight: 56, titleBlockHeight: nil) == StopCollapsedDetent.estimatedHeight)
        #expect(StopCollapsedDetent.estimatedHeight >= StopCollapsedDetent.minimumHeight)
    }

    /// Never taller than the medium detent would be: collapsed has to be the
    /// shorter rung, or a drag down from `.medium` would go nowhere.
    @Test func `Collapsed stays below half the screen`() {
        let height = StopCollapsedDetent.height(
            .init(topBarHeight: 120, titleBlockHeight: 500),
            maxDetentValue: 800
        )
        #expect(height < 400)
    }
}
