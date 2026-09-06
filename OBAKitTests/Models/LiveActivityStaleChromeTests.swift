//
//  LiveActivityStaleChromeTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

/// Pins the user-visible consequence of `ActivityKit` marking a Live Activity
/// stale (#1376). ActivityKit sets `context.isStale` from `staleDate`; the
/// widget must render something when that flips, or a frozen "3m" looks live.
@Suite(.serialized)
struct LiveActivityStaleChromeTests {

    @Test func `Warning copy is non-empty and distinct from a blank string`() {
        let text = LiveActivityStaleChrome.warningText
        #expect(!text.isEmpty)
        #expect(text != " ")
    }

    @Test func `Fresh content stays fully opaque`() {
        #expect(LiveActivityStaleChrome.contentOpacity(isStale: false) == 1.0)
    }

    @Test func `Stale content dims so a frozen countdown cannot look live`() {
        let opacity = LiveActivityStaleChrome.contentOpacity(isStale: true)
        #expect(opacity < 1.0)
        #expect(opacity > 0.0)
    }
}
