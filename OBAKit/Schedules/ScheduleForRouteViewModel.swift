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
            // Use uniquingKeysWith to handle routes that visit the same stop multiple times
            // (e.g., circular routes). Keep the first occurrence.
            let stopTimesDict = Dictionary(
                tripWithStopTimes.stopTimes.map { ($0.stopID, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            return direction.stopIDs.map { stopID in
                stopTimesDict[stopID]?.departureDate(for: scheduleDate)
            }
        }
    }

    /// Returns a sorted list of departure times for display
    /// Each row represents a trip, sorted by the trip's actual start time (earliest departure across all stops)
    var sortedDepartureTimes: [[Date?]] {
        guard let direction = currentDirection,
              let scheduleDate = scheduleData?.scheduleDate else {
            return []
        }
        let indexedTrips: [(times: [Date?], startTime: Date?)] = departureTimes.enumerated().map { index, times in
            let trip = direction.tripsWithStopTimes[index]
            return (times, actualStartTime(for: trip, scheduleDate: scheduleDate))
        }
        let sorted = indexedTrips.sorted { trip1, trip2 in
            switch (trip1.startTime, trip2.startTime) {
            case (let t1?, let t2?):
                return t1 < t2
            case (nil, _):
                return false
            case (_, nil):
                return true
            }
        }
        return sorted.map { $0.times }
    }

    /// Returns departure times for display in 24-hour format
    /// All trips shown in one continuous list without AM/PM grouping
    var departureTimesDisplay: [[Date?]] {
        return sortedDepartureTimes
    }

    // MARK: - Private Properties

    private var cancellables = Set<AnyCancellable>()

    /// Calculates the actual start time for a trip by finding the earliest departure across all stops.
    /// This is used for sorting trips chronologically, since some trips may not serve the first stop.
    private func actualStartTime(for trip: ScheduleForRoute.TripWithStopTimes, scheduleDate: Date) -> Date? {
        guard let minDepartureSeconds = trip.stopTimes.map({ $0.departureTime }).min() else {
            return nil
        }
        let startOfDay = Calendar.current.startOfDay(for: scheduleDate)
        return startOfDay.addingTimeInterval(TimeInterval(minDepartureSeconds))
    }

    // MARK: - Time Formatters

    private lazy var timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    private lazy var accessibilityTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.locale = .current
        formatter.timeZone = TimeZone.current
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
        return timeFormatter.string(from: date)
    }

    /// Formats a time with AM/PM for accessibility
    func formatTimeAccessible(_ date: Date?) -> String {
        guard let date = date else {
            return OBALoc("schedule_view.no_departure", value: "No departure", comment: "Accessibility text when there is no departure time")
        }
        return accessibilityTimeFormatter.string(from: date)
    }
}
