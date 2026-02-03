//
//  ScheduleForStopViewModel.swift
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

/// View model that manages schedule data for a specific stop
@MainActor
class ScheduleForStopViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var scheduleData: ScheduleForStop?
    @Published var selectedRouteID: RouteID?
    @Published var selectedDate: Date
    @Published var isLoading: Bool = false
    @Published var error: Error?

    // MARK: - Public Properties

    let stopID: StopID
    let application: Application

    /// The stop name, if available from schedule data
    var stopName: String {
        return scheduleData?.stop?.name ?? stopID
    }

    /// Available routes at this stop
    var availableRoutes: [(id: RouteID, name: String)] {
        guard let scheduleData = scheduleData else { return [] }
        return scheduleData.stopRouteSchedules.compactMap { routeSchedule in
            if let route = routeSchedule.route {
                return (id: routeSchedule.routeID, name: route.shortName)
            }
            return (id: routeSchedule.routeID, name: routeSchedule.routeID)
        }
    }

    // MARK: - Stop-Focused Schedule

    /// A single departure for the selected stop and route
    struct ScheduledDeparture: Identifiable, Hashable {
        // Use a composite ID to prevent duplicates (Trip ID + Time)
        var id: String {
            "\(tripID)-\(time.timeIntervalSince1970)"
        }
        let tripID: String
        let time: Date
        let headsign: String
    }

    /// All departures at this stop for the currently selected route and date
    var departuresForSelectedRoute: [ScheduledDeparture] {
        guard
            let scheduleData = scheduleData,
            let routeID = selectedRouteID,
            let routeSchedule = scheduleData.stopRouteSchedules.first(where: { $0.routeID == routeID })
        else {
            return []
        }

        var departures: [ScheduledDeparture] = []

        for directionSchedule in routeSchedule.stopRouteDirectionSchedules {
            let directionHeadsign = directionSchedule.tripHeadsign

            for stopTime in directionSchedule.scheduleStopTimes {
                let headsign = stopTime.stopHeadsign.isEmpty ? directionHeadsign : stopTime.stopHeadsign

                let departure = ScheduledDeparture(
                    tripID: stopTime.tripID,
                    time: stopTime.departureDate,
                    headsign: headsign
                )
                departures.append(departure)
            }
        }

        return departures.sorted { $0.time < $1.time }
    }

    // MARK: - Private Properties

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(stopID: StopID, application: Application, initialDate: Date = Date()) {
        self.stopID = stopID
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

    /// Fetches the schedule for the current stop and date
    func fetchSchedule() async {
        guard let apiService = application.apiService else {
            error = UnstructuredError(Strings.locationUnavailable)
            return
        }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let response = try await apiService.getScheduleForStop(stopID: stopID, date: selectedDate)
            scheduleData = response.entry

            // Validation - If the previously selected route doesn't exist on this new date, switch to the first available one.
            if let routeID = selectedRouteID,
               !(response.entry.stopRouteSchedules.contains(where: { $0.routeID == routeID })) {
                selectedRouteID = response.entry.stopRouteSchedules.first?.routeID
            } else if selectedRouteID == nil {
                selectedRouteID = response.entry.stopRouteSchedules.first?.routeID
            }
        } catch {
            self.error = error
        }
    }

    /// Select a specific route
    func selectRoute(_ routeID: RouteID) {
        selectedRouteID = routeID
    }
}
