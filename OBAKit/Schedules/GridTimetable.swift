//
//  GridTimetable.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 12/7/25.
//

import SwiftUI

/// A 2D timetable for ScheduleForRouteView used when the system font size is set to be smaller than Accessibility1.
struct GridTimetable: View {
    @EnvironmentObject var viewModel: ScheduleForRouteViewModel

    /// Column width for each stop in the timetable. Scales with Dynamic Type so the
    /// monospaced times and the stop names keep fitting at larger text sizes.
    @ScaledMetric(relativeTo: .body) private var columnWidth: CGFloat = 80

    var body: some View {
        // `formattersTimeZoneGeneration` forces a rebuild when the region zone
        // lands asynchronously (#332 / PR #1308); dates and HH:mm both depend on it.
        let _ = viewModel.formattersTimeZoneGeneration
        // Single ScrollView for both horizontal and vertical scrolling
        // LazyVStack with pinnedViews keeps header sticky during vertical scroll
        ScrollView([.horizontal, .vertical], showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    // All departure times in one continuous list (24-hour format)
                    ForEach(Array(viewModel.departureTimesDisplay.enumerated()), id: \.offset) { index, row in
                        departureRow(times: row, isAlternate: index % 2 == 1)
                        Divider()
                    }
                } header: {
                    // Stop names header - pinned during vertical scroll
                    stopHeaderRow
                }
            }
        }
        .frame(maxHeight: .infinity)
        .id(viewModel.formattersTimeZoneGeneration)
    }

    private func departureRow(times: [Date?], isAlternate: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(times.enumerated()), id: \.offset) { index, time in
                Text(viewModel.formatTime(time))
                    .font(.system(.body, design: .monospaced))
                    .frame(width: columnWidth, alignment: .leading)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
                    .accessibilityLabel(viewModel.formatTimeAccessible(time))
                if index < times.count - 1 {
                    Divider()
                }
            }
        }
        .background(isAlternate ? Color(.systemGray6) : Color.clear)
    }

    private var stopHeaderRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(viewModel.stopNames.enumerated()), id: \.offset) { index, stopName in
                stopHeader(TimetableStopName(stopName))
                    .frame(width: columnWidth, alignment: .topLeading)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(stopName)
                if index < viewModel.stopNames.count - 1 {
                    Divider()
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(.systemGroupedBackground))
    }

    /// Runs of consecutive stops often share a street ("Sand Point Way NE & NE 70th St",
    /// "Sand Point Way NE & NE 74th St", …), so the cross street is what tells columns
    /// apart. Show it in full and emphasized, with the shared street de-emphasized above it.
    private func stopHeader(_ name: TimetableStopName) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let street = name.street {
                Text(street)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(name.crossStreet)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A stop name split for display in a timetable column header.
///
/// GTFS intersection stops are conventionally named "Street & Cross Street". For those,
/// `street` is "Street &" and `crossStreet` is "Cross Street". Any other name (a station,
/// a landmark) is left whole in `crossStreet` with a `nil` street.
struct TimetableStopName: Equatable {
    let street: String?
    let crossStreet: String

    init(_ name: String) {
        if let range = name.range(of: " & ") {
            let street = name[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            let crossStreet = name[range.upperBound...].trimmingCharacters(in: .whitespaces)
            if !street.isEmpty, !crossStreet.isEmpty {
                self.street = street + " &"
                self.crossStreet = crossStreet
                return
            }
        }
        self.street = nil
        self.crossStreet = name
    }
}
