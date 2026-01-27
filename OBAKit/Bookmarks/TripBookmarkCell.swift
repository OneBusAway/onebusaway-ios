//
//  TripBookmarkCell.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import SwiftUI
import OBAKitCore

/// A UIKit table cell that displays bookmark arrival/departure information using SwiftUI.
/// Uses shared `TripBookmarkRow` view to ensure consistency with Live Activities.
final class TripBookmarkTableCell: OBAListViewCell {

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityTraits = [.button, .updatesFrequently]
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func apply(_ config: OBAContentConfiguration) {
        guard let config = config as? BookmarkArrivalContentConfiguration else { return }

        accessibilityLabel = config.viewModel.name

        guard let arrivalDepartures = config.viewModel.arrivalDepartures,
              !arrivalDepartures.isEmpty,
              let formatters = config.formatters else {
            configureWithoutData(config: config)
            return
        }
        let (routeShortName, routeHeadsign) = BookmarkNameParser.parse(config.viewModel.name)
        let firstArrival = arrivalDepartures[0]
        let statusText = buildStatusText(from: firstArrival, formatters: formatters)
        let statusUIColor = formatters.colorForScheduleStatus(firstArrival.scheduleStatus)
        let statusColor = Color(statusUIColor)
        let minutes = buildMinuteDisplays(
            arrivalDepartures: arrivalDepartures,
            formatters: formatters,
            highlightFlags: config.viewModel.arrivalDeparturesPair.map { $0.shouldHighlightOnDisplay }
        )
        let swiftUIView = TripBookmarkRow(
            routeShortName: routeShortName,
            routeHeadsign: routeHeadsign,
            statusText: statusText,
            statusColor: statusColor,
            minutes: minutes,
            isLiveActivity: false
        )
        contentConfiguration = UIHostingConfiguration {
            swiftUIView
        }
        .margins(.all, 0)
        accessibilityLabel = formatters.accessibilityLabel(for: config.viewModel)
        accessibilityValue = formatters.accessibilityValue(for: config.viewModel)
    }
    private func configureWithoutData(config: BookmarkArrivalContentConfiguration) {
        let (routeShortName, routeHeadsign) = BookmarkNameParser.parse(config.viewModel.name)

        let swiftUIView = TripBookmarkRow(
            routeShortName: routeShortName,
            routeHeadsign: routeHeadsign,
            statusText: OBALoc("loading", value: "Loading...", comment: "Loading state text"),
            statusColor: Color(ThemeColors.shared.secondaryLabel),
            minutes: [],
            isLiveActivity: false
        )

        contentConfiguration = UIHostingConfiguration {
            swiftUIView
        }
        .margins(.all, 0)
    }

    private func buildStatusText(from arrivalDeparture: ArrivalDeparture, formatters: Formatters) -> String {
        let timeString = formatters.timeFormatter.string(from: arrivalDeparture.arrivalDepartureDate)
        let deviationText: String

        if arrivalDeparture.scheduleStatus == .unknown {
            deviationText = Strings.scheduledNotRealTime
        } else {
            deviationText = formatters.formattedScheduleDeviation(for: arrivalDeparture)
        }

        return "\(timeString) - \(deviationText)"
    }

    private func buildMinuteDisplays(
        arrivalDepartures: [ArrivalDeparture],
        formatters: Formatters,
        highlightFlags: [Bool]
    ) -> [TripBookmarkRow.MinuteDisplay] {
        let displayCount = min(3, arrivalDepartures.count)
        return (0..<displayCount).map { index in
            let arrivalDeparture = arrivalDepartures[index]
            // Always show minutes for badges, regardless of schedule status
            let minuteText = formatters.shortFormattedTime(until: arrivalDeparture)
            let uiColor = formatters.backgroundColorForScheduleStatus(arrivalDeparture.scheduleStatus)
            let color = Color(uiColor)
            let shouldHighlight = index < highlightFlags.count ? highlightFlags[index] : false
            return TripBookmarkRow.MinuteDisplay(
                id: index,
                text: minuteText,
                color: color,
                isPrimary: index == 0,
                shouldHighlight: shouldHighlight
            )
        }
    }
    override func prepareForReuse() {
        super.prepareForReuse()
        contentConfiguration = nil
        accessibilityLabel = nil
        accessibilityValue = nil
    }

    override var isHighlighted: Bool {
        didSet {
            contentView.backgroundColor = isHighlighted ? ThemeColors.shared.highlightedBackgroundColor : nil
        }
    }
}
