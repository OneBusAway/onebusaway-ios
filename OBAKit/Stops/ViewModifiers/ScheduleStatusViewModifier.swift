//
//  ScheduleStatusViewModifier.swift
//  OBAKit
//
//  Created by Alan Chu on 2/9/23.
//

import SwiftUI
import OBAKitCore

private struct ScheduleStatusViewModifier: ViewModifier {
    @Environment(\.themeColors) var themeColors

    var scheduleStatus: ScheduleStatus

    func body(content: Content) -> some View {
        content
            .foregroundColor(color)
    }

    fileprivate var color: Color {
        let _color: UIColor

        switch scheduleStatus {
        case .onTime:   _color = themeColors.departureOnTime
        case .early:    _color = themeColors.departureEarly
        case .delayed:  _color = themeColors.departureLate
        default:        _color = themeColors.departureUnknown
        }

        return Color(uiColor: _color)
    }
}

extension Text {
    func scheduleStatusColor(_ scheduleStatus: ScheduleStatus) -> Text {
        self
            .foregroundColor(ScheduleStatusViewModifier(scheduleStatus: scheduleStatus).color)
    }
}

struct ScheduleStatusViewModifier_Previews: PreviewProvider {
    static var previews: some View {
        VStack(alignment: .leading) {
            Text("Arrived 3 min ago").scheduleStatusColor(.onTime)
            Text("Arriving in 1 min").scheduleStatusColor(.delayed)
            Text("Arriving now").scheduleStatusColor(.early)
            Text("Departs in 5 min").scheduleStatusColor(.unknown)
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
