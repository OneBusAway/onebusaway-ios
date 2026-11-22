//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

public extension ScheduleStatus {
    /// The SF Symbol drawn beside a countdown when Differentiate Without Color
    /// is on, so adherence doesn't rest on the countdown's tint alone. Shared by
    /// the phone's stop page, the widget and the watch.
    ///
    /// A schedule-only departure gets the clock whatever its status says: its
    /// punctuality is unknown, so it must never look on time.
    func differentiateWithoutColorGlyphName(isRealTime: Bool) -> String {
        guard isRealTime else { return "clock" }
        switch self {
        case .onTime: return "checkmark"
        case .early: return "hare.fill"
        case .delayed: return "tortoise.fill"
        case .unknown: return "clock"
        }
    }
}
