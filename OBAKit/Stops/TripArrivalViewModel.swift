//
//  TripArrivalViewModel.swift
//  OBAKit
//
//  Created by Alan Chu on 2/9/23.
//

import OBAKitCore

struct TripArrivalViewModel: Identifiable {
    let id = UUID()
    var routeAndHeadsign: String
    var date: Date

    var scheduleStatus: ScheduleStatus
    var temporalState: TemporalState
    var arrivalDepartureStatus: ArrivalDepartureStatus
    var scheduleDeviationInMinutes: Int
}

#if DEBUG

extension TripArrivalViewModel {
    static var pastDelayed: TripArrivalViewModel {
        .init(
            routeAndHeadsign: "Line 1",
            date: .now.addingTimeInterval(-(60 * 5)),
            scheduleStatus: .early,
            temporalState: .past,
            arrivalDepartureStatus: .arriving,
            scheduleDeviationInMinutes: 3
        )
    }

    static var futureExample: TripArrivalViewModel {
        .init(
            routeAndHeadsign: "142 - ASDF to whoknows",
            date: .now.addingTimeInterval(60),
            scheduleStatus: .delayed,
            temporalState: .present,
            arrivalDepartureStatus: .departing,
            scheduleDeviationInMinutes: 3
        )
    }
}

#endif
