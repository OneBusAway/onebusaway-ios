//
//  ScheduleForStopView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

// MARK: - Localized Strings

private enum StopScheduleStrings {
    static let noScheduleData = OBALoc("stop_schedule_view.no_schedule_data", value: "No schedule data available", comment: "Message shown when schedule data is not available")
    static let unableToLoad = OBALoc("stop_schedule_view.unable_to_load", value: "Unable to load schedule", comment: "Error message when schedule fails to load")
    static let date = OBALoc("stop_schedule_view.date", value: "Date", comment: "Label for date picker in schedule view")
    static let route = OBALoc("stop_schedule_view.route", value: "Route", comment: "Label for route picker in schedule view")
    static let noDepartures = OBALoc("stop_schedule_view.no_departures", value: "No departures scheduled for this date", comment: "Message when no departures are scheduled")
}

/// A SwiftUI view that displays the schedule for a specific stop
/// When a route is selected, embeds the full route timetable (RouteScheduleContentView)
struct ScheduleForStopView: View {
    @StateObject private var stopViewModel: ScheduleForStopViewModel
    @State private var routeViewModel: ScheduleForRouteViewModel?
    @Environment(\.dismiss) private var dismiss

    private let application: Application

    init(stopID: StopID, application: Application) {
        self.application = application
        _stopViewModel = StateObject(wrappedValue: ScheduleForStopViewModel(stopID: stopID, application: application))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Strings.schedules)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(Strings.close) {
                            dismiss()
                        }
                    }
                }
                .task {
                    await stopViewModel.fetchSchedule()
                }
                .onChange(of: stopViewModel.selectedRouteID) { _, newRouteID in
                    updateRouteViewModel(for: newRouteID)
                }
                .onChange(of: stopViewModel.selectedDate) { _, newDate in
                    routeViewModel?.selectedDate = newDate
                }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if stopViewModel.isLoading && stopViewModel.scheduleData == nil {
            ProgressView()
        } else if let error = stopViewModel.error {
            ErrorView(headline: StopScheduleStrings.unableToLoad, error: error) {
                Task {
                    await stopViewModel.fetchSchedule()
                }
            }
        } else if stopViewModel.scheduleData != nil {
            scheduleContent
        } else {
            Text(StopScheduleStrings.noScheduleData)
                .foregroundStyle(.secondary)
        }
    }

    private var scheduleContent: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            routeScheduleSection
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 12) {
            // Stop Name
            Text(stopViewModel.stopName)
                .font(.headline)
                .padding(.top, 8)
                .accessibilityAddTraits(.isHeader)

            // Date Picker
            HStack {
                Text(StopScheduleStrings.date)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                DatePicker(
                    "",
                    selection: $stopViewModel.selectedDate,
                    displayedComponents: [.date]
                )
                .labelsHidden()
            }
            .padding(.horizontal)

            // Route Picker (dropdown style)
            if stopViewModel.availableRoutes.count > 1 {
                HStack {
                    Text(StopScheduleStrings.route)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker(StopScheduleStrings.route, selection: Binding(
                        get: { stopViewModel.selectedRouteID ?? "" },
                        set: { stopViewModel.selectRoute($0) }
                    )) {
                        ForEach(stopViewModel.availableRoutes, id: \.id) { route in
                            Text(route.name)
                                .tag(route.id)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            } else if let route = stopViewModel.availableRoutes.first {
                HStack {
                    Text(StopScheduleStrings.route)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(route.name)
                        .font(.subheadline)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Route Schedule Section (embedded timetable)

    @ViewBuilder
    private var routeScheduleSection: some View {
        if let routeVM = routeViewModel {
            RouteScheduleContentView(viewModel: routeVM, showDatePicker: false)
                .id(routeVM.routeID)
        } else {
            ProgressView()
                .padding()
        }
    }

    // MARK: - Helper Methods

    private func updateRouteViewModel(for routeID: RouteID?) {
        guard let routeID = routeID else {
            routeViewModel = nil
            return
        }

        // Create a new route view model for the selected route
        let newRouteVM = ScheduleForRouteViewModel(
            routeID: routeID,
            application: application,
            initialDate: stopViewModel.selectedDate
        )
        routeViewModel = newRouteVM
    }
}

// MARK: - Preview

#Preview {
    // Note: Preview requires mock Application object
    Text("Schedule For Stop Preview")
}
