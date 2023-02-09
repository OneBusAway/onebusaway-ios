//
//  DepartureTimeBadgeView.swift
//  OBAKit
//
//  Created by Alan Chu on 2/9/23.
//

import SwiftUI
import OBAKitCore

struct DepartureTimeBadgeView: View {
    @Environment(\.themeColors) var themeColors

    var date: Date
    var temporalState: TemporalState
    var scheduleStatus: ScheduleStatus

    var body: some View {
        Text(text)
            .foregroundColor(color)
            .font(.headline)
    }

    var text: String {
        let untilMinutes = Int(date.timeIntervalSinceNow / 60.0)

        switch temporalState {
        case .present: return OBALoc("formatters.now", value: "NOW", comment: "Short formatted time text for arrivals/departures occurring now.")
        default:
            let formatString = OBALoc("formatters.short_time_fmt", value: "%dm", comment: "Short formatted time text for arrivals/departures. Example: 7m means that this event happens 7 minutes in the future. -7m means 7 minutes in the past.")
            return String(format: formatString, untilMinutes)
        }
    }

    var color: Color {
        let _color: UIColor

        switch scheduleStatus {
        case .onTime:   _color = themeColors.departureOnTimeBackground
        case .early:    _color = themeColors.departureEarlyBackground
        case .delayed:  _color = themeColors.departureLateBackground
        default:        _color = themeColors.departureUnknownBackground
        }

        return Color(uiColor: _color)
    }
}

struct DepartureTimeBadgeView_Previews: PreviewProvider {
    static var previews: some View {
        DepartureTimeBadgeView(date: .now.addingTimeInterval(60 * 5), temporalState: .future, scheduleStatus: .delayed)
    }
}
