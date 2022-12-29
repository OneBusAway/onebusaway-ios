//
//  StopArrivalItem.swift
//  OBAKit
//
//  Created by Alan Chu on 2/15/21.
//

import OBAKitCore

struct ArrivalDepartureItem: OBAListViewItem {
    var configuration: OBAListViewItemConfiguration {
        return .custom(ArrivalDepartureContentConfiguration(viewModel: self))
    }

    static var customCellType: OBAListViewCell.Type? {
        return StopArrivalCell.self
    }

    var onSelectAction: OBAListViewAction<ArrivalDepartureItem>?

    var alarmAction: OBAListViewAction<ArrivalDepartureItem>?
    var bookmarkAction: OBAListViewAction<ArrivalDepartureItem>?
    var shareAction: OBAListViewAction<ArrivalDepartureItem>?

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

    let isAlarmAvailable: Bool
    let isDeepLinkingAvailable: Bool

    /// Real-time occupancy status information.
    let occupancyStatus: ArrivalDeparture.OccupancyStatus?

    /// Historical occupancy status information.
    let historicalOccupancyStatus: ArrivalDeparture.OccupancyStatus?

    /// Whether to highlight the time (to indicate a change) when this item is displayed on the list.
    let highlightTimeOnDisplay: Bool

    var trailingContextualActions: [OBAListViewContextualAction<ArrivalDepartureItem>]? {
        var actions: [OBAListViewContextualAction<ArrivalDepartureItem>] = []

        if let bookmarkAction = self.bookmarkAction {
            let bookmarkAction = OBAListViewContextualAction(
                style: .normal,
                title: Strings.bookmark,
                image: Icons.addBookmark,
                backgroundColor: ThemeColors.shared.brand,
                hidesWhenSelected: true,
                item: self,
                handler: bookmarkAction)

            actions.append(bookmarkAction)
        }

        if isAlarmAvailable, let alarmAction = self.alarmAction {
            let alarmAction = OBAListViewContextualAction(
                style: .normal,
                title: Strings.alarm,
                image: Icons.addAlarm,
                backgroundColor: ThemeColors.shared.blue,
                hidesWhenSelected: true,
                item: self,
                handler: alarmAction)

            actions.append(alarmAction)
        }

        if isDeepLinkingAvailable, let shareAction = self.shareAction {
            let shareAction = OBAListViewContextualAction(
                style: .normal,
                title: Strings.share,
                image: Icons.shareFill,
                backgroundColor: UIColor.purple,
                hidesWhenSelected: true,
                item: self,
                handler: shareAction)

            actions.append(shareAction)
        }

        return actions
    }

    init(arrivalDeparture: ArrivalDeparture,
         isAlarmAvailable: Bool,
         isDeepLinkingAvailable: Bool,
         highlightTimeOnDisplay: Bool = false,
         onSelectAction: OBAListViewAction<ArrivalDepartureItem>? = nil,
         alarmAction: OBAListViewAction<ArrivalDepartureItem>? = nil,
         bookmarkAction: OBAListViewAction<ArrivalDepartureItem>? = nil,
         shareAction: OBAListViewAction<ArrivalDepartureItem>? = nil) {

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

        self.isAlarmAvailable = isAlarmAvailable
        self.isDeepLinkingAvailable = isDeepLinkingAvailable
        self.highlightTimeOnDisplay = highlightTimeOnDisplay

        self.onSelectAction = onSelectAction
        self.alarmAction = alarmAction
        self.bookmarkAction = bookmarkAction
        self.shareAction = shareAction
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

struct ArrivalDepartureContentConfiguration: OBAContentConfiguration {
    var deemphasizePastEvents: Bool = true
    var viewModel: ArrivalDepartureItem
    var formatters: Formatters?

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
        return DepartureTimeBadge.Configuration(
            arrivalDepartureMinutes: viewModel.arrivalDepartureMinutes,
            arrivalDepartureStatus: viewModel.arrivalDepartureStatus,
            temporalState: viewModel.temporalState,
            scheduleStatus: viewModel.scheduleStatus,
            formatters: formatters)
    }

    var accessibilityLabel: String? {
        formatters?.accessibilityLabelForArrivalDeparture(routeAndHeadsign: viewModel.name)
    }

    var accessibilityValue: String? {
        return formatters?.accessibilityValueForArrivalDeparture(arrivalDepartureDate: viewModel.arrivalDepartureDate, arrivalDepartureMinutes: viewModel.arrivalDepartureMinutes, arrivalDepartureStatus: viewModel.arrivalDepartureStatus, temporalState: viewModel.temporalState, scheduleStatus: viewModel.scheduleStatus)
    }
}
