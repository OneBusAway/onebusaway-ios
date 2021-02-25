//
//  StopArrivalItem.swift
//  OBAKit
//
//  Created by Alan Chu on 2/15/21.
//

import OBAKitCore

struct ArrivalDepartureItem: OBAListViewItem {
    var contentConfiguration: OBAContentConfiguration {
        var config = OBAListRowConfiguration(
            text: name,
            secondaryText: "\(scheduledDate.timeIntervalSinceReferenceDate)",
            appearance: .subtitle,
            accessoryType: .disclosureIndicator)
        return config
    }

    var onSelectAction: OBAListViewAction<ArrivalDepartureItem>?

    let identifier: String
    let routeID: RouteID
    let stopID: StopID

    let name: String
    let scheduledDate: Date
    let scheduleStatus: ScheduleStatus
    let temporalState: TemporalState

    let isAlarmAvailable: Bool

    init(arrivalDeparture: ArrivalDeparture, isAlarmAvailable: Bool) {
        self.identifier = arrivalDeparture.id
        self.routeID = arrivalDeparture.routeID
        self.stopID = arrivalDeparture.stopID
        self.name = arrivalDeparture.routeAndHeadsign

        self.scheduledDate = arrivalDeparture.scheduledDate
        self.scheduleStatus = arrivalDeparture.scheduleStatus
        self.temporalState = arrivalDeparture.temporalState

        self.isAlarmAvailable = isAlarmAvailable
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(identifier)
    }

    static func == (lhs: ArrivalDepartureItem, rhs: ArrivalDepartureItem) -> Bool {
        return lhs.routeID == rhs.routeID &&
            lhs.stopID == rhs.stopID &&
            lhs.name == rhs.name &&
            lhs.scheduledDate == rhs.scheduledDate &&
            lhs.scheduleStatus == rhs.scheduleStatus &&
            lhs.temporalState == rhs.temporalState
    }
}
