//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
import UIKit
import OBAKitCore

/// The Differentiate Without Color glyphs shared by the stop page, the widget
/// and the watch.
@Suite(.serialized)
struct ScheduleStatusGlyphTests {

    @Test func `Each real-time status has its own glyph`() {
        #expect(ScheduleStatus.onTime.differentiateWithoutColorGlyphName(isRealTime: true) == "checkmark")
        #expect(ScheduleStatus.early.differentiateWithoutColorGlyphName(isRealTime: true) == "hare.fill")
        #expect(ScheduleStatus.delayed.differentiateWithoutColorGlyphName(isRealTime: true) == "tortoise.fill")
        #expect(ScheduleStatus.unknown.differentiateWithoutColorGlyphName(isRealTime: true) == "clock")
    }

    @Test func `A schedule-only departure always gets the clock, never a punctuality glyph`() {
        for status in [ScheduleStatus.unknown, .early, .onTime, .delayed] {
            #expect(status.differentiateWithoutColorGlyphName(isRealTime: false) == "clock")
        }
    }

    @Test @MainActor func `Every glyph is an SF Symbol`() {
        for status in [ScheduleStatus.unknown, .early, .onTime, .delayed] {
            for isRealTime in [true, false] {
                let name = status.differentiateWithoutColorGlyphName(isRealTime: isRealTime)
                #expect(UIImage(systemName: name) != nil, "\(name) isn't an SF Symbol")
            }
        }
    }
}
