//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore

/// The single home of the Stop page's status visual language: countdowns,
/// adherence labels, and the real-time hard gate. When `isRealTime == false`
/// the UI must show a clock glyph, gray text, no occupancy, and never claim
/// the trip is "on time" — a scheduled bus's punctuality is unknown.
struct DepartureStatus {
    let isRealTime: Bool
    let scheduleStatus: ScheduleStatus
    let deviationMinutes: Int

    init(arrivalDeparture: ArrivalDeparture) {
        self.init(
            isRealTime: arrivalDeparture.predicted,
            scheduleStatus: arrivalDeparture.scheduleStatus,
            deviationMinutes: arrivalDeparture.deviationFromScheduleInMinutes
        )
    }

    init(isRealTime: Bool, scheduleStatus: ScheduleStatus, deviationMinutes: Int) {
        self.isRealTime = isRealTime
        self.scheduleStatus = scheduleStatus
        self.deviationMinutes = deviationMinutes
    }

    var showsOccupancy: Bool { isRealTime }

    var color: UIColor {
        guard isRealTime else { return .secondaryLabel }
        switch scheduleStatus {
        case .onTime: return ThemeColors.shared.departureOnTime
        case .early: return ThemeColors.shared.departureEarly
        case .delayed: return ThemeColors.shared.departureLate
        default: return .secondaryLabel
        }
    }

    /// Adherence label shown when there's no real-time signal; deliberately
    /// avoids claiming the bus is on time. Used by both the no-signal and the
    /// unknown-status paths below.
    private static var scheduleDataLabel: String {
        OBALoc("stop_page.status.schedule_data", value: "schedule data", comment: "Adherence label for a departure with no real-time signal; deliberately avoids claiming the bus is on time.")
    }

    var label: String {
        guard isRealTime else {
            return Self.scheduleDataLabel
        }
        switch scheduleStatus {
        case .onTime:
            return OBALoc("stop_page.status.on_time", value: "on time", comment: "Adherence label for an on-time departure")
        case .delayed:
            let fmt = OBALoc("stop_page.status.late_fmt", value: "%d min late", comment: "Adherence label for a late departure. %d is minutes late.")
            return String(format: fmt, abs(deviationMinutes))
        case .early:
            let fmt = OBALoc("stop_page.status.early_fmt", value: "%d min early", comment: "Adherence label for an early departure. %d is minutes early.")
            return String(format: fmt, abs(deviationMinutes))
        default:
            return Self.scheduleDataLabel
        }
    }

    var accessibilityStatusDescription: String {
        if isRealTime {
            let fmt = OBALoc("stop_page.status.a11y_live_fmt", value: "live tracking, %@", comment: "VoiceOver status suffix for a live departure. %@ is the adherence label.")
            return String(format: fmt, label)
        }
        return OBALoc("stop_page.status.a11y_scheduled", value: "scheduled time only, no live data", comment: "VoiceOver status suffix for a schedule-only departure")
    }
}
