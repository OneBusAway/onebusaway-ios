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
    var liveActivityAction: OBAListViewAction<ArrivalDepartureItem>?
    var scheduleAction: OBAListViewAction<ArrivalDepartureItem>?

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

    /// Real-time occupancy status information.
    let occupancyStatus: ArrivalDeparture.OccupancyStatus?

    /// Historical occupancy status information.
    let historicalOccupancyStatus: ArrivalDeparture.OccupancyStatus?

    /// Whether to highlight the time (to indicate a change) when this item is displayed on the list.
    let highlightTimeOnDisplay: Bool

    /// When set, minutes are computed relative to the transfer arrival time instead of now.
    let transferContext: TransferContext?

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

        if #available(iOS 16.2, *), let liveActivityAction = self.liveActivityAction {
            let action = OBAListViewContextualAction(
                style: .normal,
                title: OBALoc("live_activity.swipe_action.title", value: "Live", comment: "Swipe action title to start a Live Activity from an arrival row"),
                image: UIImage(systemName: "livephoto"),
                backgroundColor: UIColor.systemPurple,
                hidesWhenSelected: true,
                item: self,
                handler: liveActivityAction)
            actions.append(action)
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

        if let scheduleAction = self.scheduleAction {
            let scheduleAction = OBAListViewContextualAction(
                style: .normal,
                title: Strings.schedule,
                image: UIImage(systemName: "calendar"),
                backgroundColor: UIColor.systemTeal,
                hidesWhenSelected: true,
                item: self,
                handler: scheduleAction)

            actions.append(scheduleAction)
        }

        return actions
    }

    init(arrivalDeparture: ArrivalDeparture,
         isAlarmAvailable: Bool,
         highlightTimeOnDisplay: Bool = false,
         transferContext: TransferContext? = nil,
         onSelectAction: OBAListViewAction<ArrivalDepartureItem>? = nil,
         alarmAction: OBAListViewAction<ArrivalDepartureItem>? = nil,
         bookmarkAction: OBAListViewAction<ArrivalDepartureItem>? = nil,
         scheduleAction: OBAListViewAction<ArrivalDepartureItem>? = nil) {

        self.arrivalDepartureID = arrivalDeparture.id
        self.routeID = arrivalDeparture.routeID
        self.stopID = arrivalDeparture.stopID
        self.name = arrivalDeparture.routeAndHeadsign

        self.scheduledDate = arrivalDeparture.scheduledDate
        self.scheduleStatus = arrivalDeparture.scheduleStatus
        self.deviationFromScheduleInMinutes = arrivalDeparture.deviationFromScheduleInMinutes
        self.transferContext = transferContext

        if let transferContext = transferContext {
            self.temporalState = transferContext.temporalState(for: arrivalDeparture.arrivalDepartureDate)
            self.arrivalDepartureMinutes = transferContext.minutesUntilDeparture(from: arrivalDeparture.arrivalDepartureDate)
        } else {
            self.temporalState = arrivalDeparture.temporalState
            self.arrivalDepartureMinutes = arrivalDeparture.arrivalDepartureMinutes
        }

        self.arrivalDepartureDate = arrivalDeparture.arrivalDepartureDate
        self.arrivalDepartureStatus = arrivalDeparture.arrivalDepartureStatus

        self.occupancyStatus = arrivalDeparture.occupancyStatus
        self.historicalOccupancyStatus = arrivalDeparture.historicalOccupancyStatus

        self.isAlarmAvailable = isAlarmAvailable
        self.highlightTimeOnDisplay = highlightTimeOnDisplay

        self.onSelectAction = onSelectAction
        self.alarmAction = alarmAction
        self.bookmarkAction = bookmarkAction
        self.scheduleAction = scheduleAction
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
        hasher.combine(transferContext)
    }

    static func == (lhs: ArrivalDepartureItem, rhs: ArrivalDepartureItem) -> Bool {
        return lhs.id == rhs.id &&
            lhs.arrivalDepartureID == rhs.arrivalDepartureID &&
            lhs.routeID == rhs.routeID &&
            lhs.stopID == rhs.stopID &&
            lhs.name == rhs.name &&
            lhs.scheduledDate == rhs.scheduledDate &&
            lhs.scheduleStatus == rhs.scheduleStatus &&
            lhs.temporalState == rhs.temporalState &&
            lhs.transferContext == rhs.transferContext
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
        if viewModel.transferContext != nil {
            return formatters?.shortFormattedTransferTime(minutes: viewModel.arrivalDepartureMinutes)
        }
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
