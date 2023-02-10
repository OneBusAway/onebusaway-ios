//
//  TripArrivalViewModel.swift
//  OBAKit
//
//  Created by Alan Chu on 2/9/23.
//

import OBAKitCore

struct TripArrivalViewModel: Identifiable, Hashable {
    let id: String
    var routeAndHeadsign: String
    var date: Date

    var scheduleStatus: ScheduleStatus
    var temporalState: TemporalState
    var arrivalDepartureStatus: ArrivalDepartureStatus
    var scheduleDeviationInMinutes: Int

    init(
        id: String = UUID().uuidString,
        routeAndHeadsign: String,
        date: Date,
        scheduleStatus: ScheduleStatus,
        temporalState: TemporalState,
        arrivalDepartureStatus: ArrivalDepartureStatus,
        scheduleDeviationInMinutes: Int
    ) {
        self.id = id
        self.routeAndHeadsign = routeAndHeadsign
        self.date = date
        self.scheduleStatus = scheduleStatus
        self.temporalState = temporalState
        self.arrivalDepartureStatus = arrivalDepartureStatus
        self.scheduleDeviationInMinutes = scheduleDeviationInMinutes
    }

    static func fromArrivalDeparture(_ arrDep: ArrivalDeparture) -> Self {
        return self.init(
            id: arrDep.id,
            routeAndHeadsign: arrDep.routeAndHeadsign,
            date: arrDep.arrivalDepartureDate,
            scheduleStatus: arrDep.scheduleStatus,
            temporalState: arrDep.temporalState,
            arrivalDepartureStatus: arrDep.arrivalDepartureStatus,
            scheduleDeviationInMinutes: arrDep.deviationFromScheduleInMinutes
        )
    }
}

// MARK: - View models for loading (use with redacted view modifier)

extension TripArrivalViewModel {
    static var loadingIndicator: TripArrivalViewModel {
        .init(routeAndHeadsign: "-------------", date: .now, scheduleStatus: .unknown, temporalState: .present, arrivalDepartureStatus: .departing, scheduleDeviationInMinutes: 0)
    }
}


// MARK: - View models for Xcode Previews
#if DEBUG

extension TripArrivalViewModel {
    static var all: [TripArrivalViewModel] {
        return [
            .pastArrivingEarly,
            .presentDepartingDelayed
        ].sorted(by: \.date)
    }

    static var pastArrivingEarly: TripArrivalViewModel {
        .init(
            routeAndHeadsign: "Past Arrived Early",
            date: .now.addingTimeInterval(-(60 * 5)),
            scheduleStatus: .early,
            temporalState: .past,
            arrivalDepartureStatus: .arriving,
            scheduleDeviationInMinutes: 3
        )
    }

    static var presentDepartingDelayed: TripArrivalViewModel {
        .init(
            routeAndHeadsign: "NOW Departing Late",
            date: .now.addingTimeInterval(60),
            scheduleStatus: .delayed,
            temporalState: .present,
            arrivalDepartureStatus: .departing,
            scheduleDeviationInMinutes: 3
        )
    }
}

#endif
