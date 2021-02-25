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

    init(arrivalDeparture: ArrivalDeparture, isAlarmAvailable: Bool) {
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

struct ArrivalDepartureContentConfiguration: OBAContentConfiguration {
    var deemphasizePastEvents: Bool = true
    var viewModel: ArrivalDepartureItem
    var formatters: Formatters?

    var obaContentView: (OBAContentView & ReuseIdentifierProviding).Type {
        return StopArrivalCell.self
    }

    var fullAttributedExplaination: NSAttributedString? {
        guard let formatters = formatters else { return nil }

        let arrDepTime = formatters.timeFormatter.string(from: viewModel.scheduledDate)
        let explanationText: String
        if viewModel.scheduleStatus == .unknown {
            explanationText = Strings.scheduledNotRealTime
        } else {
            explanationText = formatters.formattedScheduleDeviation(
                temporalState: viewModel.temporalState,
                status: viewModel.arrivalDepartureStatus,
                scheduleDeviation: viewModel.deviationFromScheduleInMinutes)
        }

        let scheduleStatusColor = formatters.colorForScheduleStatus(viewModel.scheduleStatus)
        let timeExplanationFont = UIFont.preferredFont(forTextStyle: .footnote)

        let attributedExplanation = NSMutableAttributedString(
            string: "\(arrDepTime) - ",
            attributes: [NSAttributedString.Key.font: timeExplanationFont])

        let explanation = NSAttributedString(
            string: explanationText,
            attributes: [NSAttributedString.Key.font: timeExplanationFont,
                         NSAttributedString.Key.foregroundColor: scheduleStatusColor])

        attributedExplanation.append(explanation)

        return attributedExplanation
    }

    var untilMinutesText: String? {
        guard let formatters = formatters else { return nil }
        return formatters.shortFormattedTime(untilMinutes: viewModel.arrivalDepartureMinutes, temporalState: viewModel.temporalState)
    }

    var colorForScheduleStatus: UIColor? {
        guard let formatters = formatters else { return nil }
        return formatters.colorForScheduleStatus(viewModel.scheduleStatus)
    }

    var accessibilityTimeLabelText: String? {
        guard let formatters = formatters else { return nil }
        return formatters.timeFormatter.string(from: viewModel.arrivalDepartureDate)
    }

    var accessibilityScheduleDeviationText: String? {
        guard let formatters = formatters else { return nil }
        if viewModel.scheduleStatus == .unknown {
            return Strings.scheduledNotRealTime
        } else {
            return formatters.formattedScheduleDeviation(
                temporalState: viewModel.temporalState,
                status: viewModel.arrivalDepartureStatus,
                scheduleDeviation: viewModel.deviationFromScheduleInMinutes)
        }
    }

    var accessibilityScheduleDeviationLabelTextColor: UIColor? {
        guard let formatters = formatters else { return nil }
        return formatters.colorForScheduleStatus(viewModel.scheduleStatus)
    }

    var accessibilityRelativeTimeBadgeConfiguration: Any? { return nil }

    var accessibilityLabel: String? {
        return String(format: OBALoc("voiceover.arrivaldeparture_route_fmt", value: "Route %@", comment: "VoiceOver text describing the name of a route in a verbose fashion to compensate for no visuals."), viewModel.name)
    }

    var accessibilityValue: String? {
        guard let formatters = formatters else { return nil }
        let arrDepTime = formatters.timeFormatter.string(from: viewModel.arrivalDepartureDate)
        let arrDepMins = abs(viewModel.arrivalDepartureMinutes)
        let apply: (String) -> String = { String(format: $0, arrDepMins, arrDepTime) }

        let scheduleStatus: String
        switch (viewModel.arrivalDepartureStatus,
                viewModel.temporalState,
                viewModel.scheduleStatus == .unknown) {
            // Is a past event, regardless of realtime data availability.
            case (.arriving, .past, _): scheduleStatus = apply(OBALoc("voiceover.arrivaldeparture_arrived_x_minutes_ago_fmt", value: "arrived %d minutes ago at %@.", comment: "VoiceOver text describing a route that has already arrived, regardless of realtime data availability."))
            case (.departing, .past, _): scheduleStatus = apply(OBALoc("voiceover.arrivaldeparture_departed_x_minutes_ago_fmt", value: "departed %d minutes ago at %@.", comment: "VoiceOver text describing a route that has already departed, regardless of realtime data availability."))

            // Is a current event, regardless of realtime data availability.
            case (.arriving, .present, _): scheduleStatus = OBALoc("voiceover.arrivaldeparture_arriving_now", value: "arriving now!", comment: "VoiceOver text describing a route that is arriving now, regardless of realtime data availability.")
            case (.departing, .present, _): scheduleStatus = OBALoc("voiceover.arrivaldeparture_departing_now", value: "departing now!", comment: "VoiceOver text describing a route that is departing now, regardless of realtime data availability.")

            // Has realtime data and is a future event.
            case (.arriving, .future, false): scheduleStatus = apply(OBALoc("voiceover.arrivaldeparture_arriving_in_x_minutes", value: "arriving in %d minutes at %@.", comment: "VoiceOver text describing a future arrival that is based off realtime data."))
            case (.departing, .future, false): scheduleStatus = apply(OBALoc("voiceover.arrivaldeparture_departing_in_x_minutes_fmt", value: "departing in %d minutes at %@.", comment: "VoiceOver text describing a future departure that is based off realtime data."))

            // No realtime data and is a future event.
            case (.arriving, .future, true): scheduleStatus = apply(OBALoc("voiceover.arrivaldeparture_scheduled_arrives_in_x_minutes_fmt", value: "scheduled to arrive in %d minutes at %@.", comment: "VoiceOver text describing a route that is scheduled to arrive (no realtime data was available)."))
            case (.departing, .future, true): scheduleStatus = apply(OBALoc("voiceover.arrivaldeparture_scheduled_departs_in_x_minutes_fmt", value: "scheduled to depart in %d minutes at %@.", comment: "VoiceOver text describing a route that is scheduled to depart. (no realtime data was available)"))
        }

        return scheduleStatus
    }
}
