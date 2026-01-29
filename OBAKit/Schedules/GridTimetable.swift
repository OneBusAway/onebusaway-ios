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

    /// Column width for each stop in the timetable
    private let columnWidth: CGFloat = 80

    var body: some View {
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
                Text(stopName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .frame(width: columnWidth, alignment: .leading)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
                    .accessibilityLabel(stopName)
                if index < viewModel.stopNames.count - 1 {
                    Divider()
                }
            }
        }
        .background(Color(.systemGroupedBackground))
    }
}
