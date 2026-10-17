//
//  TripStopRunRow.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// What a collapsed run of stops says, on screen and to VoiceOver. Separate from
/// the row so the wording is testable without rendering anything.
enum TripStopRunCopy {

    /// "12 stops • 9:52 AM – 10:22 AM", or just "12 stops" when the feed gave
    /// none of the run's stops a time.
    static func title(for group: TripStopListModel.CollapsedGroup, time: (Date) -> String) -> String {
        let count = CountPlural.format(
            OBALoc("trip_page.stop_list.run_count_fmt", value: "%d stops", comment: "Count in a collapsed run of stops on the trip page, e.g. '12 stops'. %d is the number of stops. Plural forms live in Localizable.stringsdict; this value is only the not-found fallback."),
            count: group.rows.count
        )
        let range = timeRange(
            for: group,
            time: time,
            format: OBALoc("trip_page.stop_list.run_time_range_fmt", value: "%1$@ – %2$@", comment: "Time range of a collapsed run of stops on the trip page. %1$@ is the first stop's time, %2$@ the last's.")
        )
        guard let range else { return count }
        return String(
            format: OBALoc("trip_page.stop_list.run_summary_fmt", value: "%1$@ • %2$@", comment: "A collapsed run of stops on the trip page: %1$@ is the count ('12 stops'), %2$@ the time range ('9:52 AM – 10:22 AM')."),
            count, range
        )
    }

    /// "12 passed stops, 9:52 AM to 10:22 AM". Says which kind of run it is,
    /// which on screen only the rail's color does.
    static func accessibilityLabel(for group: TripStopListModel.CollapsedGroup, time: (Date) -> String) -> String {
        let format = switch group.kind {
        case .passed:
            OBALoc("trip_page.stop_list.a11y_run_passed_fmt", value: "%d passed stops", comment: "VoiceOver label for a collapsed run of stops the vehicle has passed, e.g. '12 passed stops'. Plural forms live in Localizable.stringsdict; this value is only the not-found fallback.")
        case .approaching:
            OBALoc("trip_page.stop_list.a11y_run_approaching_fmt", value: "%d stops before your stop", comment: "VoiceOver label for a collapsed run of stops between the vehicle and the rider's stop, e.g. '5 stops before your stop'. Plural forms live in Localizable.stringsdict; this value is only the not-found fallback.")
        }
        let count = CountPlural.format(format, count: group.rows.count)
        let range = timeRange(
            for: group,
            time: time,
            format: OBALoc("trip_page.stop_list.a11y_run_time_range_fmt", value: "%1$@ to %2$@", comment: "VoiceOver time range of a collapsed run of stops. %1$@ is the first stop's time, %2$@ the last's, e.g. '9:52 AM to 10:22 AM'.")
        )
        return [count, range].compactMap { $0 }.joined(separator: ", ")
    }

    /// SwiftUI has no expanded-state trait, so the state is spoken as the value —
    /// in the same words as the stop page's other collapsible headers.
    static func accessibilityValue(isExpanded: Bool) -> String {
        isExpanded
            ? OBALoc("stop_page.grouped.a11y_expanded", value: "expanded", comment: "VoiceOver value of a collapsible header or grouped route card whose contents are showing.")
            : OBALoc("stop_page.grouped.a11y_collapsed", value: "collapsed", comment: "VoiceOver value of a collapsible header or grouped route card whose contents are hidden.")
    }

    /// The first and last times, the one time if they agree or only one is
    /// known, or `nil` if none is.
    private static func timeRange(for group: TripStopListModel.CollapsedGroup, time: (Date) -> String, format: String) -> String? {
        guard let first = group.firstDate, let last = group.lastDate else { return nil }
        let start = time(first), end = time(last)
        return start == end ? start : String(format: format, start, end)
    }
}

/// The row standing in for a run of stops. One control for both kinds of run:
/// the rail's color is the only difference, gray behind the vehicle and the route
/// color ahead of it, so the line reads as continuous through the list.
struct TripStopRunRow: View {
    let group: TripStopListModel.CollapsedGroup
    let isExpanded: Bool
    let isFirst: Bool
    /// Whether the connector coming down into this row is behind the vehicle.
    let segmentAboveIsSpent: Bool
    let routeColor: Color
    let compactMode: Bool
    let onToggle: () -> Void

    @Environment(\.obaFormatters) private var formatters

    @ScaledMetric(relativeTo: .body) private var gapDotSize: CGFloat = 3

    private func time(_ date: Date) -> String { formatters.timeFormatter.string(from: date) }

    var body: some View {
        HStack(spacing: 12) {
            connector
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text(TripStopRunCopy.title(for: group, time: time))
                        .font(.subheadline)
                        .foregroundStyle(group.isPassed ? Color(uiColor: .tertiaryLabel) : .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(.vertical, StopTripSpacing.stopRowVertical(compactMode))
                // A run is never the last line: the vehicle's stop or the rider's
                // stop always follows it.
                Divider()
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TripStopRunCopy.accessibilityLabel(for: group, time: time))
        .accessibilityValue(TripStopRunCopy.accessibilityValue(isExpanded: isExpanded))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onToggle() }
    }

    /// The rail runs straight through, with a short column of dots standing in
    /// for the hidden stops' markers.
    private var connector: some View {
        TripStopRail(
            isFirst: isFirst,
            isLast: false,
            aboveIsSpent: segmentAboveIsSpent,
            belowIsSpent: group.isPassed,
            routeColor: routeColor
        ) {
            VStack(spacing: gapDotSize) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                        .frame(width: gapDotSize, height: gapDotSize)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
