//
//  StopArrivalItem.swift
//  OBAKit
//
//  Created by Alan Chu on 2/15/21.
//

import UIKit
import OBAKitCore

nonisolated struct ArrivalDepartureItem: OBAListViewItem {
    var configuration: OBAListViewItemConfiguration {
        return .custom(ArrivalDepartureContentConfiguration(viewModel: self))
    }

    static var customCellType: OBAListViewCell.Type? {
        return StopArrivalCell.self
    }

    var onSelectAction: OBAListViewAction<ArrivalDepartureItem>?

    let id: UUID = UUID()
    let arrivalDepartureID: String
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

    /// Real-time occupancy status information.
    let occupancyStatus: ArrivalDeparture.OccupancyStatus?

    /// Historical occupancy status information.
    let historicalOccupancyStatus: ArrivalDeparture.OccupancyStatus?

    init(arrivalDeparture: ArrivalDeparture, onSelectAction: OBAListViewAction<ArrivalDepartureItem>? = nil) {
        self.arrivalDepartureID = arrivalDeparture.id
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

        self.occupancyStatus = arrivalDeparture.occupancyStatus
        self.historicalOccupancyStatus = arrivalDeparture.historicalOccupancyStatus

        self.onSelectAction = onSelectAction
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(arrivalDepartureID)
        hasher.combine(routeID)
        hasher.combine(stopID)
        hasher.combine(name)
        hasher.combine(scheduledDate)
        hasher.combine(scheduleStatus)
        hasher.combine(temporalState)
    }

    static func == (lhs: ArrivalDepartureItem, rhs: ArrivalDepartureItem) -> Bool {
        return lhs.id == rhs.id &&
            lhs.arrivalDepartureID == rhs.arrivalDepartureID &&
            lhs.routeID == rhs.routeID &&
            lhs.stopID == rhs.stopID &&
            lhs.name == rhs.name &&
            lhs.scheduledDate == rhs.scheduledDate &&
            lhs.scheduleStatus == rhs.scheduleStatus &&
            lhs.temporalState == rhs.temporalState
    }
}

nonisolated struct ArrivalDepartureContentConfiguration: OBAContentConfiguration {
    var deemphasizePastEvents: Bool = true
    var viewModel: ArrivalDepartureItem
    var formatters: Formatters?

    /// The zone the rider's device is in, which decides whether the clock below
    /// carries a timezone badge. Defaults to the real one; injectable so a test
    /// can fix both sides of that comparison instead of depending on the machine
    /// it runs on.
    var deviceTimeZone: TimeZone = .current

    var obaContentView: (OBAContentView & ReuseIdentifierProviding).Type {
        return StopArrivalCell.self
    }

    var fullAttributedExplanation: NSAttributedString? {
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

    /// Goes through `formattedClockTime` rather than `timeFormatter` directly so
    /// this carries the timezone badge (#332). `StopArrivalView` populates one
    /// `accessibilityTimeLabel` from two places — the `arrivalDeparture` didSet
    /// and this configuration — and at accessibility sizes that label is the only
    /// clock on screen, so a bare region-zone time would read as local (#1438).
    var accessibilityTimeLabelText: String? {
        guard let formatters else { return nil }
        return formatters.formattedClockTime(viewModel.arrivalDepartureDate, deviceTimeZone: deviceTimeZone)
    }

    var accessibilityScheduleDeviationText: String? {
        guard let formatters = formatters else { return nil }
        return formatters.deviationLabel(
            scheduleStatus: viewModel.scheduleStatus,
            temporalState: viewModel.temporalState,
            arrivalDepartureStatus: viewModel.arrivalDepartureStatus,
            scheduleDeviation: viewModel.deviationFromScheduleInMinutes)
    }

    var accessibilityScheduleDeviationLabelTextColor: UIColor? {
        return formatters?.colorForScheduleStatus(viewModel.scheduleStatus)
    }

    var departureTimeBadgeConfiguration: DepartureTimeBadge.Configuration? {
        guard let formatters = formatters else { return nil }
        return DepartureTimeBadge.Configuration(
            arrivalDepartureMinutes: viewModel.arrivalDepartureMinutes,
            arrivalDepartureStatus: viewModel.arrivalDepartureStatus,
            temporalState: viewModel.temporalState,
            scheduleStatus: viewModel.scheduleStatus,
            scheduleDeviation: viewModel.deviationFromScheduleInMinutes,
            formatters: formatters)
    }

    var accessibilityLabel: String? {
        formatters?.accessibilityLabelForArrivalDeparture(routeAndHeadsign: viewModel.name)
    }

    var accessibilityValue: String? {
        return formatters?.accessibilityValueForArrivalDeparture(arrivalDepartureDate: viewModel.arrivalDepartureDate, arrivalDepartureMinutes: viewModel.arrivalDepartureMinutes, arrivalDepartureStatus: viewModel.arrivalDepartureStatus, temporalState: viewModel.temporalState, scheduleStatus: viewModel.scheduleStatus)
    }
}
