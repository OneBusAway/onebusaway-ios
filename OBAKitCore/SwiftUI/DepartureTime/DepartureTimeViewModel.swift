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

    public init(arrivalDepartureDate: Date, temporalState: TemporalState, scheduleStatus: ScheduleStatus) {
        self.arrivalDepartureDate = arrivalDepartureDate
        self.temporalState = temporalState
        self.scheduleStatus = scheduleStatus
    }

    public init(withArrivalDeparture arrivalDeparture: ArrivalDeparture) {
        self.init(arrivalDepartureDate: arrivalDeparture.arrivalDepartureDate,
                  temporalState: arrivalDeparture.temporalState,
                  scheduleStatus: arrivalDeparture.scheduleStatus)
    }
}

#if DEBUG
extension DepartureTimeViewModel {
    init(minutes: Int, temporalState: TemporalState, scheduleStatus: ScheduleStatus) {
        let date = Calendar.current.date(byAdding: .minute, value: minutes, to: Date())!
        self.init(arrivalDepartureDate: date, temporalState: temporalState, scheduleStatus: scheduleStatus)
    }

    static public var DEBUG_departingNOWOnTime: Self {
        return .init(minutes: 1, temporalState: .present, scheduleStatus: .onTime)
    }

    static public var DEBUG_departingIn12MinutesOnTime: Self {
        return .init(minutes: 12, temporalState: .future, scheduleStatus: .onTime)
    }

    static public var DEBUG_departingIn20MinutesScheduled: Self {
        return .init(minutes: 20, temporalState: .future, scheduleStatus: .unknown)
    }

    static public var DEBUG_departed11MinutesAgoEarly: Self {
        return .init(minutes: 11, temporalState: .past, scheduleStatus: .early)
    }

    static public var DEBUG_arrivingIn3MinutesLate: Self {
        return .init(minutes: 3, temporalState: .future, scheduleStatus: .delayed)
    }

    static public var DEBUG_arrivingIn124MinutesScheduled: Self {
        return .init(minutes: 124, temporalState: .future, scheduleStatus: .unknown)
    }
}
#endif
