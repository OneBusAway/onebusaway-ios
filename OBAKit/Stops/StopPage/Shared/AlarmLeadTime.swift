//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// Lead-time rules for departure alarms: user-adjustable within 1–15 minutes,
/// but never scheduled at or past the departure itself.
enum AlarmLeadTime {
    static let minimumMinutes = 1
    static let maximumMinutes = 15
    static let defaultMinutes = 5

    /// Clamps a requested lead time into the valid range for a departure
    /// `minutesUntilDeparture` away, or nil when no valid lead time exists
    /// (mirrors `StopViewModel.canCreateAlarm`'s `> 1` gate).
    static func clamped(_ requested: Int, minutesUntilDeparture: Int) -> Int? {
        guard minutesUntilDeparture > 1 else { return nil }
        let ceiling = min(maximumMinutes, minutesUntilDeparture - 1)
        return min(max(requested, minimumMinutes), ceiling)
    }
}
