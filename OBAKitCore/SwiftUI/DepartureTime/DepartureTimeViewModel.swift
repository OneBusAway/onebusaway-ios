//
//  DepartureTimeViewModel.swift
//  OBAKitCore
//
//  Created by Alan Chu on 5/20/21.
//

public struct DepartureTimeViewModel: Hashable, Equatable {
    public let arrivalDepartureDate: Date
    public let temporalState: TemporalState
    public let scheduleStatus: ScheduleStatus
    public let arrivalDepartureStatus: ArrivalDepartureStatus

    public init(arrivalDepartureDate: Date, temporalState: TemporalState, scheduleStatus: ScheduleStatus, arrivalDepartureStatus: ArrivalDepartureStatus) {
        self.arrivalDepartureDate = arrivalDepartureDate
        self.temporalState = temporalState
        self.scheduleStatus = scheduleStatus
        self.arrivalDepartureStatus = arrivalDepartureStatus
    }

    public init(withArrivalDeparture arrivalDeparture: ArrivalDeparture) {
        self.init(arrivalDepartureDate: arrivalDeparture.arrivalDepartureDate,
                  temporalState: arrivalDeparture.temporalState,
                  scheduleStatus: arrivalDeparture.scheduleStatus,
                  arrivalDepartureStatus: arrivalDeparture.arrivalDepartureStatus)
    }
}

#if DEBUG
extension DepartureTimeViewModel {
    init(minutes: Int, temporalState: TemporalState, scheduleStatus: ScheduleStatus, arrivalDepartureStatus: ArrivalDepartureStatus) {
        let date = Calendar.current.date(byAdding: .minute, value: minutes, to: Date())!
        self.init(arrivalDepartureDate: date, temporalState: temporalState, scheduleStatus: scheduleStatus, arrivalDepartureStatus: arrivalDepartureStatus)
    }

    static public var DEBUG_departingNOWOnTime: Self {
        return .init(minutes: 1, temporalState: .present, scheduleStatus: .onTime, arrivalDepartureStatus: .departing)
    }

    static public var DEBUG_departingIn12MinutesOnTime: Self {
        return .init(minutes: 12, temporalState: .future, scheduleStatus: .onTime, arrivalDepartureStatus: .departing)
    }

    static public var DEBUG_departingIn20MinutesScheduled: Self {
        return .init(minutes: 20, temporalState: .future, scheduleStatus: .unknown, arrivalDepartureStatus: .departing)
    }

    static public var DEBUG_departed11MinutesAgoEarly: Self {
        return .init(minutes: 11, temporalState: .past, scheduleStatus: .early, arrivalDepartureStatus: .departing)
    }

    static public var DEBUG_arrivingIn3MinutesLate: Self {
        return .init(minutes: 3, temporalState: .future, scheduleStatus: .delayed, arrivalDepartureStatus: .arriving)
    }

    static public var DEBUG_arrivingIn124MinutesScheduled: Self {
        return .init(minutes: 124, temporalState: .future, scheduleStatus: .unknown, arrivalDepartureStatus: .arriving)
    }
}
#endif
