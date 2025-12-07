//
//  ScheduleForRouteView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

// MARK: - Localized Strings

private enum ScheduleStrings {
    static let noScheduleData = OBALoc("schedule_view.no_schedule_data", value: "No schedule data available", comment: "Message shown when schedule data is not available")
    static let unableToLoad = OBALoc("schedule_view.unable_to_load", value: "Unable to load schedule", comment: "Error message when schedule fails to load")
    static let date = OBALoc("schedule_view.date", value: "Date", comment: "Label for date picker in schedule view")
    static let direction = OBALoc("schedule_view.direction", value: "Direction", comment: "Label for direction picker in schedule view")
    static let noStopsFound = OBALoc("schedule_view.no_stops_found", value: "No stops found for this direction", comment: "Message when no stops are available for the selected direction")

    static func directionNumber(_ number: Int) -> String {
        return OBALoc("schedule_view.direction_number_fmt", value: "Direction %d", comment: "Default direction label when no headsign is available")
            .replacingOccurrences(of: "%d", with: "\(number)")
    }

    static func toHeadsign(_ headsign: String) -> String {
        return OBALoc("schedule_view.to_headsign_fmt", value: "To: %@", comment: "Headsign label showing destination")
            .replacingOccurrences(of: "%@", with: headsign)
    }
}

/// Internal content view that can be embedded without NavigationStack
/// Use this when embedding the route schedule inside another view (e.g., ScheduleForStopView)
struct RouteScheduleContentView: View {
    @ObservedObject var viewModel: ScheduleForRouteViewModel
    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    /// Whether to show the date picker (false when embedded in ScheduleForStopView which has its own)
    var showDatePicker: Bool = true

    var body: some View {
        content
            .task {
                if viewModel.scheduleData == nil {
                    await viewModel.fetchSchedule()
                }
            }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.scheduleData == nil {
            ProgressView()
        } else if let error = viewModel.error {
            ErrorView(headline: ScheduleStrings.unableToLoad, error: error) {
                Task {
                    await viewModel.fetchSchedule()
                }
            }
        } else if viewModel.scheduleData != nil {
            scheduleContent
        } else {
            Text(ScheduleStrings.noScheduleData)
                .foregroundStyle(.secondary)
        }
    }

    private var scheduleContent: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            timetableSection
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 12) {
            // Date Picker (optional)
            if showDatePicker {
                HStack {
                    Text(ScheduleStrings.date)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    DatePicker(
                        "",
                        selection: $viewModel.selectedDate,
                        displayedComponents: [.date]
                    )
                    .labelsHidden()
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }

            // Direction Picker (if multiple directions)
            if viewModel.directions.count > 1 {
                Picker(ScheduleStrings.direction, selection: $viewModel.selectedDirectionIndex) {
                    ForEach(Array(viewModel.directions.enumerated()), id: \.offset) { index, direction in
                        Text(direction.tripHeadsigns.first ?? ScheduleStrings.directionNumber(index + 1))
                            .tag(index)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, showDatePicker ? 0 : 8)
            }

            // Current headsign display
            if !viewModel.currentHeadsign.isEmpty {
                Text(ScheduleStrings.toHeadsign(viewModel.currentHeadsign))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Timetable Section

    @ViewBuilder
    private var timetableSection: some View {
        if viewModel.stopNames.isEmpty {
            Text(ScheduleStrings.noStopsFound)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if dynamicTypeSize.isAccessibilitySize {
            AccessibilityTimetable()
                .environmentObject(viewModel)
        } else {
            GridTimetable()
                .environmentObject(viewModel)
        }
    }
}

/// A SwiftUI view that displays the schedule for a specific route
/// This is the standalone version with NavigationStack for direct presentation
struct ScheduleForRouteView: View {
    @StateObject private var viewModel: ScheduleForRouteViewModel
    @Environment(\.dismiss) private var dismiss

    init(routeID: RouteID, application: Application) {
        _viewModel = StateObject(wrappedValue: ScheduleForRouteViewModel(routeID: routeID, application: application))
    }

    var body: some View {
        NavigationStack {
            RouteScheduleContentView(viewModel: viewModel)
                .navigationTitle(viewModel.routeName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(Strings.close) {
                            dismiss()
                        }
                    }
                }
        }
    }
}

// MARK: - Preview

#Preview {
    // Note: Preview requires mock Application object
    Text("Schedule Preview")
}
