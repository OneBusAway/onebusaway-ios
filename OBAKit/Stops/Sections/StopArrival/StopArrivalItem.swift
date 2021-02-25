//
//  StopArrivalItem.swift
//  OBAKit
//
//  Created by Alan Chu on 2/15/21.
//

import OBAKitCore

struct ArrivalDepartureItem: OBAListViewItem {
    var contentConfiguration: OBAContentConfiguration {
        return ArrivalDepartureContentConfiguration(viewModel: self)
    }

    static var customCellType: OBAListViewCell.Type? {
        return StopArrivalCell.self
    }

    var onSelectAction: OBAListViewAction<ArrivalDepartureItem>?

    let identifier: String
    let routeID: RouteID
    let stopID: StopID

    let name: String
    let scheduledDate: Date
    let scheduleStatus: ScheduleStatus
    let deviationFromScheduleInMinutes: Int
    let temporalState: TemporalState

    let arrivalDepartureDate: Date
    let arrivalDepartureStatus: ArrivalDepartureStatus
    let arrivalDepartureMinutes: Int

    let isAlarmAvailable: Bool

    init(arrivalDeparture: ArrivalDeparture, isAlarmAvailable: Bool, onSelectAction: OBAListViewAction<ArrivalDepartureItem>? = nil) {
        self.identifier = arrivalDeparture.id
        self.routeID = arrivalDeparture.routeID
        self.stopID = arrivalDeparture.stopID
        self.name = arrivalDeparture.routeAndHeadsign

        self.scheduledDate = arrivalDeparture.scheduledDate
        self.scheduleStatus = arrivalDeparture.scheduleStatus
        self.deviationFromScheduleInMinutes = arrivalDeparture.deviationFromScheduleInMinutes
        self.temporalState = arrivalDeparture.temporalState

        self.arrivalDepartureDate = arrivalDeparture.arrivalDepartureDate
        self.arrivalDepartureStatus = arrivalDeparture.arrivalDepartureStatus
        self.arrivalDepartureMinutes = arrivalDeparture.arrivalDepartureMinutes

        self.isAlarmAvailable = isAlarmAvailable
        self.onSelectAction = onSelectAction
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(identifier)
    }

    static func == (lhs: ArrivalDepartureItem, rhs: ArrivalDepartureItem) -> Bool {
        return lhs.identifier == rhs.identifier &&
            lhs.routeID == rhs.routeID &&
            lhs.stopID == rhs.stopID &&
            lhs.name == rhs.name &&
            lhs.scheduledDate == rhs.scheduledDate &&
            lhs.scheduleStatus == rhs.scheduleStatus &&
            lhs.temporalState == rhs.temporalState
    }
}

struct ArrivalDepartureContentConfiguration: OBAContentConfiguration {
    var deemphasizePastEvents: Bool = true
    var viewModel: ArrivalDepartureItem
    var formatters: Formatters?

    var obaContentView: (OBAContentView & ReuseIdentifierProviding).Type {
        return StopArrivalCell.self
    }

    var fullAttributedExplaination: NSAttributedString? {
        return formatters?.fullAttributedArrivalDepartureExplanation(
            arrivalDepartureDate: viewModel.arrivalDepartureDate,
            scheduleStatus: viewModel.scheduleStatus,
            temporalState: viewModel.temporalState,
            arrivalDepartureStatus: viewModel.arrivalDepartureStatus,
            scheduleDeviationInMinutes: viewModel.deviationFromScheduleInMinutes)
    }

    var untilMinutesText: String? {
        return formatters?.shortFormattedTime(untilMinutes: viewModel.arrivalDepartureMinutes, temporalState: viewModel.temporalState)
    }

    var colorForScheduleStatus: UIColor? {
        return formatters?.colorForScheduleStatus(viewModel.scheduleStatus)
    }

    var accessibilityTimeLabelText: String? {
        return formatters?.timeFormatter.string(from: viewModel.arrivalDepartureDate)
    }

    var accessibilityScheduleDeviationText: String? {
        guard let formatters = formatters else { return nil }
        if viewModel.scheduleStatus == .unknown {
            return Strings.scheduledNotRealTime
        } else {
            return formatters.formattedScheduleDeviation(
                temporalState: viewModel.temporalState,
                arrivalDepartureStatus: viewModel.arrivalDepartureStatus,
                scheduleDeviation: viewModel.deviationFromScheduleInMinutes)
        }
    }

    var accessibilityScheduleDeviationLabelTextColor: UIColor? {
        return formatters?.colorForScheduleStatus(viewModel.scheduleStatus)
    }

    var departureTimeBadgeConfiguration: DepartureTimeBadge.Configuration? {
        guard let formatters = formatters else { return nil }
        return DepartureTimeBadge.Configuration(arrivalDepartureMinutes: viewModel.arrivalDepartureMinutes, temporalState: viewModel.temporalState, scheduleStatus: viewModel.scheduleStatus, formatters: formatters)
    }

    var accessibilityLabel: String? {
        formatters?.accessibilityLabelForArrivalDeparture(routeAndHeadsign: viewModel.name)
    }

    var accessibilityValue: String? {
        return formatters?.accessibilityValueForArrivalDeparture(arrivalDepartureDate: viewModel.arrivalDepartureDate, arrivalDepartureMinutes: viewModel.arrivalDepartureMinutes, arrivalDepartureStatus: viewModel.arrivalDepartureStatus, temporalState: viewModel.temporalState, scheduleStatus: viewModel.scheduleStatus)
    }
}
