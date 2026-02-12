//
//  ArrivalDepartureViewObject.swift
//  OBAKit
//
//  Created by Alan Chu on 2/12/23.
//

import SwiftUI
import OBAKitCore

class ArrivalDepartureViewObject: Identifiable, ObservableObject/*, Comparable*/ {
    let id: ArrivalDeparture.Identifier

    @Published var routeAndHeadsign: String

    @Published var arrivalDepartureDate: Date
    @Published var arrivalDepartureStatus: ArrivalDepartureStatus
    @Published var temporalState: TemporalState
    @Published var scheduleStatus: ScheduleStatus
    @Published var scheduleDeviationInMinutes: Int

    init(_ arrivalDeparture: ArrivalDeparture) {
        self.id = arrivalDeparture.id

        self.routeAndHeadsign = arrivalDeparture.routeAndHeadsign
        self.arrivalDepartureDate = arrivalDeparture.arrivalDepartureDate
        self.arrivalDepartureStatus = arrivalDeparture.arrivalDepartureStatus
        self.temporalState = arrivalDeparture.temporalState
        self.scheduleStatus = arrivalDeparture.scheduleStatus
        self.scheduleDeviationInMinutes = arrivalDeparture.deviationFromScheduleInMinutes
    }

    init(
        id: ArrivalDeparture.Identifier,
        routeAndHeadsign: String,
        arrivalDepartureDate: Date,
        arrivalDepartureStatus: ArrivalDepartureStatus,
        temporalState: TemporalState,
        scheduleStatus: ScheduleStatus,
        scheduleDeviationInMinutes: Int
    ) {
        self.id = id
        self.routeAndHeadsign = routeAndHeadsign
        self.arrivalDepartureDate = arrivalDepartureDate
        self.arrivalDepartureStatus = arrivalDepartureStatus
        self.temporalState = temporalState
        self.scheduleStatus = scheduleStatus
        self.scheduleDeviationInMinutes = scheduleDeviationInMinutes
    }

    @MainActor
    func update(with newValues: ArrivalDepartureViewObject) {
        precondition(newValues.id == self.id)

        self.routeAndHeadsign = newValues.routeAndHeadsign
        self.arrivalDepartureDate = newValues.arrivalDepartureDate
        self.arrivalDepartureStatus = newValues.arrivalDepartureStatus
        self.temporalState = newValues.temporalState
        self.scheduleStatus = newValues.scheduleStatus
        self.scheduleDeviationInMinutes = newValues.scheduleDeviationInMinutes
    }

    @objc func debugQuickLookObject() -> Any? {
        """
        Route & Headsign: \(routeAndHeadsign)
        Date: \(arrivalDepartureDate)
        Status: \(arrivalDepartureStatus)
        State: \(temporalState)
        Schedule Status: \(scheduleStatus)
        Schedule Deviation: \(scheduleDeviationInMinutes) mins
        """
    }
}

// MARK: - Xcode Previews

#if DEBUG

extension ArrivalDepartureViewObject {
    static var all: [ArrivalDepartureViewObject] {
        return [
            .pastArrivingEarly,
            .presentDepartingDelayed
        ].sorted(by: \.arrivalDepartureDate)
    }

    private static var startOfToday: Date {
        return Calendar.current.startOfDay(for: .now)
    }

    static func nowOffsetBy(minutes: Int) -> Date {
        return .now.addingTimeInterval(60 * Double(minutes))
    }

    static var pastArrivingEarly: ArrivalDepartureViewObject {
        let id = ArrivalDeparture.Identifier(serviceDate: startOfToday, stopID: "1_1234", routeID: "1_4567", tripID: "1_987654321", stopSequence: 0)
        return .init(
            id: id,
            routeAndHeadsign: "4567 - Past Arrived Early",
            arrivalDepartureDate: nowOffsetBy(minutes: -5),
            arrivalDepartureStatus: .arriving,
            temporalState: .past,
            scheduleStatus: .early,
            scheduleDeviationInMinutes: 3
        )
    }

    static var presentDepartingDelayed: ArrivalDepartureViewObject {
        let id = ArrivalDeparture.Identifier(serviceDate: startOfToday, stopID: "1_1234", routeID: "1_4321", tripID: "1_123454321", stopSequence: 0)
        return .init(
            id: id,
            routeAndHeadsign: "4321 - NOW Departing Late",
            arrivalDepartureDate: nowOffsetBy(minutes: 1),
            arrivalDepartureStatus: .departing,
            temporalState: .present,
            scheduleStatus: .delayed,
            scheduleDeviationInMinutes: 3
        )
    }
}

#endif
