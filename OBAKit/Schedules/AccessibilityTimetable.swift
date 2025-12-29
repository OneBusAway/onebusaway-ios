//
//  AccessibilityTimetable.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 12/7/25.
//

import SwiftUI

/// A list-style timetable for ScheduleForRouteView used when the system font size is set to Accessibility1 or larger.
struct AccessibilityTimetable: View {
    @EnvironmentObject var viewModel: ScheduleForRouteViewModel

    var body: some View {
        List {
            Section {
                // All departure times in one section (24-hour format, no AM/PM grouping)
                ForEach(Array(viewModel.departureTimesDisplay.enumerated()), id: \.offset) { _, tripTimes in
                    accessibilityTripRow(times: tripTimes)
                }
            } header: {
                Text("Schedule")
                    .font(.headline)
            }
        }
        .listStyle(.plain)
    }

    private func accessibilityTripRow(times: [Date?]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(zip(viewModel.stopNames, times).enumerated()), id: \.offset) { index, pair in
                let (stopName, time) = pair
                VStack(spacing: 0) {
                    if index > 0 {
                        Divider()
                    }
                    HStack {
                        Text(stopName)
                            .font(.body)
                        Spacer()
                        Text(viewModel.formatTimeAccessible(time))
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }
}
