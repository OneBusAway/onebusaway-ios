//
//  ScheduleForRouteViewModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Combine
import SwiftUI
import OBAKitCore

// MARK: - Time Period Grouping

/// Represents a group of departure times for a specific time period (AM or PM)
struct TimePeriodGroup: Identifiable {
    let id: String
    let label: String
    let times: [[Date?]]
}

/// View model that manages schedule data for a specific route
@MainActor
class ScheduleForRouteViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var scheduleData: ScheduleForRoute?
    @Published var selectedDate: Date
    @Published var selectedDirectionIndex: Int = 0
    @Published var isLoading: Bool = false
    @Published var error: Error?

    // MARK: - Public Properties

    let routeID: RouteID
    let application: Application

    /// The route name, if available from schedule data
    var routeName: String {
        if let route = scheduleData?.route {
            return route.shortName
        }
        return routeID
    }

    /// The available directions for the current schedule
    var directions: [ScheduleForRoute.StopTripGrouping] {
        return scheduleData?.stopTripGroupings ?? []
    }

    /// The currently selected direction
    var currentDirection: ScheduleForRoute.StopTripGrouping? {
        guard !directions.isEmpty, selectedDirectionIndex < directions.count else {
            return nil
        }
        return directions[selectedDirectionIndex]
    }

    /// The headsign for the current direction
    var currentHeadsign: String {
        return currentDirection?.tripHeadsigns.first ?? ""
    }

    /// Stop names for the current direction
    var stopNames: [String] {
        guard let direction = currentDirection else { return [] }
        return direction.stops.map { $0.name }
    }

    /// Stop IDs for the current direction
    var stopIDs: [StopID] {
        guard let direction = currentDirection else { return [] }
        return direction.stopIDs
    }

    /// Returns a matrix of departure times: rows = trips, columns = stops
    /// Times are formatted as Date objects for display
    /// Uses dictionary lookup for O(n*m) instead of O(n*m*k) complexity
    var departureTimes: [[Date?]] {
        guard let direction = currentDirection,
              let scheduleDate = scheduleData?.scheduleDate else {
            return []
        }

        return direction.tripsWithStopTimes.map { tripWithStopTimes in
            // Pre-compute dictionary for O(1) lookups instead of O(k) first(where:)
            let stopTimesDict = Dictionary(
                uniqueKeysWithValues: tripWithStopTimes.stopTimes.map { ($0.stopID, $0) }
            )
            return direction.stopIDs.map { stopID in
                stopTimesDict[stopID]?.departureDate(for: scheduleDate)
            }
        }
    }

    /// Returns a sorted list of departure times for display
    /// Each row represents a trip, sorted by the earliest non-nil departure time
    var sortedDepartureTimes: [[Date?]] {
        let times = departureTimes
        return times.sorted { row1, row2 in
            // Find the first non-nil departure time for each row
            let date1 = row1.first { $0 != nil } ?? nil
            let date2 = row2.first { $0 != nil } ?? nil

            // If both have dates, sort by date
            switch (date1, date2) {
            case (let d1?, let d2?):
                return d1 < d2
            case (nil, _):
                return false
            case (_, nil):
                return true
            }
        }
    }

    /// Returns departure times grouped by time period (AM/PM)
    /// Each group contains trips where the earliest departure is in that period
    var departureTimesByPeriod: [TimePeriodGroup] {
        let sorted = sortedDepartureTimes
        let calendar = Calendar.current

        var amTrips: [[Date?]] = []
        var pmTrips: [[Date?]] = []

        for row in sorted {
            // Find the earliest non-nil departure time for this row
            guard let earliestTime = row.first(where: { $0 != nil }), let date = earliestTime else {
                // If no departure times at all, default to PM
                pmTrips.append(row)
                continue
            }

            let hour = calendar.component(.hour, from: date)
            if hour < 12 {
                amTrips.append(row)
            } else {
                pmTrips.append(row)
            }
        }

        var groups: [TimePeriodGroup] = []

        if !amTrips.isEmpty {
            groups.append(TimePeriodGroup(
                id: "AM",
                label: OBALoc("schedule_view.am_period", value: "AM", comment: "Morning time period label"),
                times: amTrips
            ))
        }

        if !pmTrips.isEmpty {
            groups.append(TimePeriodGroup(
                id: "PM",
                label: OBALoc("schedule_view.pm_period", value: "PM", comment: "Afternoon/evening time period label"),
                times: pmTrips
            ))
        }

        return groups
    }

    // MARK: - Private Properties

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Static Formatters (for performance)

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        return formatter
    }()

    private static let timeFormatterWithAMPM: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    // MARK: - Initialization

    init(routeID: RouteID, application: Application, initialDate: Date = Date()) {
        self.routeID = routeID
        self.application = application
        self.selectedDate = initialDate

        // Observe date changes and refetch
        $selectedDate
            .dropFirst()
            .removeDuplicates { Calendar.current.isDate($0, inSameDayAs: $1) }
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.fetchSchedule()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Public Methods

    /// Fetches the schedule for the current route and date
    func fetchSchedule() async {
        guard let apiService = application.apiService else {
            error = UnstructuredError(Strings.locationUnavailable)
            return
        }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let response = try await apiService.getScheduleForRoute(routeID: routeID, date: selectedDate)
            scheduleData = response.entry
        } catch {
            self.error = error
        }
    }

    /// Formats a time for display in the timetable
    func formatTime(_ date: Date?) -> String {
        guard let date = date else { return "-" }
        return Self.timeFormatter.string(from: date)
    }

    /// Formats a time with AM/PM for accessibility
    func formatTimeAccessible(_ date: Date?) -> String {
        guard let date = date else {
            return OBALoc("schedule_view.no_departure", value: "No departure", comment: "Accessibility text when there is no departure time")
        }
        return Self.timeFormatterWithAMPM.string(from: date)
    }
}
