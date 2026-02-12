//
//  StopArrivalExplanationView.swift
//  OBAKit
//
//  Created by Alan Chu on 2/9/23.
//

import SwiftUI
import OBAKitCore

struct StopArrivalExplanationView: View {
    @Environment(\.obaFormatters) var formatter

    var arrivalDepartureDate: Date
    var scheduleStatus: ScheduleStatus
    var temporalState: TemporalState
    var arrivalDepartureStatus: ArrivalDepartureStatus
    var scheduleDeviationInMinutes: Int

    var body: some View {
        Text(arrivalDepartureDate, style: .time) +
        Text(" - ") +
        fullExplanationText
            .scheduleStatusColor(scheduleStatus)
    }

    var fullExplanationText: Text {
        if scheduleStatus == .unknown {
            return Text(Strings.scheduledNotRealTime)
        } else {
            return Text(formatter.formattedScheduleDeviation(temporalState: temporalState, arrivalDepartureStatus: arrivalDepartureStatus, scheduleDeviation: scheduleDeviationInMinutes))
        }
    }
}

struct StopArrivalExplanationView_Previews: PreviewProvider {
    static var previews: some View {
        StopArrivalExplanationView(arrivalDepartureDate: .now.addingTimeInterval(60), scheduleStatus: .onTime, temporalState: .present, arrivalDepartureStatus: .departing, scheduleDeviationInMinutes: 0)
    }
}
