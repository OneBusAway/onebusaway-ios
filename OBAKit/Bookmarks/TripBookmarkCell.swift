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

        // Use structured data directly from the bookmark instead of parsing the display name.
        let routeShortName = config.viewModel.bookmark.routeShortName ?? config.viewModel.name
        let routeHeadsign = config.viewModel.bookmark.tripHeadsign ?? ""

        accessibilityLabel = config.viewModel.name

        guard let arrivalDepartures = config.viewModel.arrivalDepartures,
              !arrivalDepartures.isEmpty,
              let formatters = config.formatters else {
            applySwiftUIView(TripBookmarkRow(
                routeShortName: routeShortName,
                routeHeadsign: routeHeadsign,
                statusText: OBALoc("loading", value: "Loading...", comment: "Loading state text"),
                statusColor: Color(ThemeColors.shared.secondaryLabel),
                minutes: [],
                isLiveActivity: false
            ))
            return
        }

        let firstArrival = arrivalDepartures[0]
        let statusText = TripBookmarkRow.buildStatusText(from: firstArrival, formatters: formatters)
        let statusUIColor = formatters.colorForScheduleStatus(firstArrival.scheduleStatus)
        let minutes = buildMinuteDisplays(
            arrivalDepartures: arrivalDepartures,
            formatters: formatters,
            highlightFlags: config.viewModel.arrivalDeparturesPair.map { $0.shouldHighlightOnDisplay }
        )

        let swiftUIView = TripBookmarkRow(
            routeShortName: routeShortName,
            routeHeadsign: routeHeadsign,
            statusText: statusText,
            statusColor: Color(statusUIColor),
            minutes: minutes,
            isLiveActivity: false
        )

        applySwiftUIView(swiftUIView)

        accessibilityLabel = formatters.accessibilityLabel(for: config.viewModel)
        accessibilityValue = formatters.accessibilityValue(for: config.viewModel)
    }

    /// Applies a `TripBookmarkRow` SwiftUI view as the cell's content configuration.
    private func applySwiftUIView(_ view: TripBookmarkRow) {
        contentConfiguration = UIHostingConfiguration {
            view
        }
        .margins(.all, 0)
    }

    private func buildMinuteDisplays(
        arrivalDepartures: [ArrivalDeparture],
        formatters: Formatters,
        highlightFlags: [Bool]
    ) -> [TripBookmarkRow.MinuteDisplay] {
        let displayCount = min(3, arrivalDepartures.count)
        return (0..<displayCount).map { index in
            let arrivalDeparture = arrivalDepartures[index]
            let minuteText = formatters.shortFormattedTime(until: arrivalDeparture)
            let uiColor = formatters.backgroundColorForScheduleStatus(arrivalDeparture.scheduleStatus)
            let shouldHighlight = index < highlightFlags.count ? highlightFlags[index] : false
            return TripBookmarkRow.MinuteDisplay(
                text: minuteText,
                color: Color(uiColor),
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
