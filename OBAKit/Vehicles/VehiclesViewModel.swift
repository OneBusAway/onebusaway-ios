//
//  VehiclesViewModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Combine
import MapKit
import SwiftUI
import OBAKitCore

/// View model that manages vehicle positions state and auto-refresh
@MainActor
class VehiclesViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var vehicles: [RealtimeVehicle] = []
    @Published var feedStatuses: [AgencyFeedStatus] = []
    @Published var isLoading: Bool = false
    @Published var error: Error?
    @Published var lastUpdated: Date?
    @Published var cameraPosition: MapCameraPosition = .automatic

    // MARK: - Agency Filter Properties

    /// Total number of agencies available
    var totalAgencyCount: Int {
        feedStatuses.count
    }

    /// Number of enabled agencies
    var enabledAgencyCount: Int {
        feedStatuses.filter { isAgencyEnabled($0.id) }.count
    }

    /// Whether all agencies are currently enabled
    var allAgenciesEnabled: Bool {
        application.userDataStore.disabledVehicleFeedAgencyIDs.isEmpty
    }

    // MARK: - Private Properties

    private let application: Application
    private var refreshTask: Task<Void, Never>?
    private var allAgencyIDs: [String] = []

    /// Auto-refresh interval in seconds
    private let refreshInterval: TimeInterval = 30

    // MARK: - Initialization

    init(application: Application) {
        self.application = application
    }

    deinit {
        refreshTask?.cancel()
    }

    // MARK: - Public Methods

    /// Fetches vehicle positions for all agencies in the current region
    func fetchVehicles() async {
        guard let apiService = application.apiService else {
            print("[VehiclesVM] ERROR: No apiService available")
            return
        }
        guard !isLoading else {
            print("[VehiclesVM] Skipping fetch - already loading")
            return
        }

        isLoading = true
        error = nil

        print("[VehiclesVM] ========== Starting vehicle fetch ==========")

        do {
            // 1. Fetch agencies
            let agencies = try await apiService.getAgenciesWithCoverage().list
            print("[VehiclesVM] Fetched \(agencies.count) agencies")

            // Store all agency IDs for toggle all functionality
            self.allAgencyIDs = agencies.map { $0.agencyID }

            // 2. Fetch vehicles for enabled agencies, create status for all
            typealias FetchResult = (vehicles: [RealtimeVehicle], status: AgencyFeedStatus)
            var allStatuses: [AgencyFeedStatus] = []
            var allVehicles: [RealtimeVehicle] = []

            let results = await withTaskGroup(of: FetchResult?.self) { group -> [FetchResult] in
                for agencyWithCoverage in agencies {
                    let agencyID = agencyWithCoverage.agencyID
                    let agencyName = agencyWithCoverage.agency?.name ?? "Unknown"

                    if isAgencyEnabled(agencyID) {
                        // Fetch vehicles for enabled agencies
                        group.addTask {
                            await self.fetchVehiclesForAgency(
                                agencyID,
                                agencyName: agencyName,
                                agency: agencyWithCoverage.agency
                            )
                        }
                    } else {
                        // Create a skipped status for disabled agencies (no network call)
                        var status = AgencyFeedStatus(id: agencyID, agencyName: agencyName)
                        status.isSkipped = true
                        allStatuses.append(status)
                    }
                }

                var results: [FetchResult] = []
                for await result in group {
                    if let result = result {
                        results.append(result)
                    }
                }
                return results
            }

            allVehicles = results.flatMap { $0.vehicles }
            allStatuses.append(contentsOf: results.map { $0.status })

            self.vehicles = allVehicles
            self.feedStatuses = allStatuses.sorted { $0.agencyName < $1.agencyName }
            self.lastUpdated = Date()
            print("[VehiclesVM] ========== Fetch complete: \(self.vehicles.count) total vehicles ==========")
        } catch {
            self.error = error
            print("[VehiclesVM] ERROR fetching agencies: \(error)")
        }

        isLoading = false
    }

    /// Starts automatic refresh of vehicle positions
    func startAutoRefresh() {
        stopAutoRefresh()

        refreshTask = Task { [weak self] in
            guard let self = self else { return }

            while !Task.isCancelled {
                await self.fetchVehicles()
                try? await Task.sleep(for: .seconds(self.refreshInterval))
            }
        }
    }

    /// Stops automatic refresh
    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// Manually triggers a refresh
    func refresh() async {
        await fetchVehicles()
    }

    /// Centers the map on the current region
    func centerOnCurrentRegion() {
        if let region = application.regionsService.currentRegion {
            cameraPosition = .region(MKCoordinateRegion(region.serviceRect))
        }
    }

    // MARK: - Agency Filter Methods

    /// Returns whether the specified agency is enabled for vehicle display
    func isAgencyEnabled(_ agencyID: String) -> Bool {
        application.userDataStore.isAgencyEnabledForVehicleFeed(agencyID: agencyID)
    }

    /// Sets whether the specified agency is enabled for vehicle display
    func setAgencyEnabled(_ enabled: Bool, agencyID: String) {
        application.userDataStore.setAgencyEnabledForVehicleFeed(enabled, agencyID: agencyID)
        objectWillChange.send()
        // Trigger refresh to update vehicle display
        Task {
            await fetchVehicles()
        }
    }

    /// Toggles all agencies on or off
    func toggleAllAgencies() {
        let newState = !allAgenciesEnabled
        application.userDataStore.setAllAgenciesEnabledForVehicleFeed(newState, agencyIDs: allAgencyIDs)
        objectWillChange.send()
        // Trigger refresh to update vehicle display
        Task {
            await fetchVehicles()
        }
    }

    // MARK: - Private Methods

    private nonisolated func fetchVehiclesForAgency(_ agencyID: String, agencyName: String, agency: Agency?) async -> (vehicles: [RealtimeVehicle], status: AgencyFeedStatus) {
        var status = AgencyFeedStatus(id: agencyID, agencyName: agencyName)

        let urlString = "https://api.pugetsound.onebusaway.org/api/gtfs_realtime/vehicle-positions-for-agency/\(agencyID).pb?key=org.onebusaway.iphone"
        guard let url = URL(string: urlString) else {
            print("[VehiclesVM] \(agencyName) (Agency ID \(agencyID))")
            print("[VehiclesVM] \(agencyID): ERROR - Invalid URL")
            status.error = .invalidURL
            status.lastFetchedAt = Date()
            return ([], status)
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            print("[VehiclesVM] \(agencyName) (Agency ID \(agencyID))")

            status.dataSize = data.count
            status.lastFetchedAt = Date()

            // Log HTTP response details
            if let httpResponse = response as? HTTPURLResponse {
                status.httpStatusCode = httpResponse.statusCode
                print("[VehiclesVM] \(agencyID): HTTP \(httpResponse.statusCode), \(data.count) bytes")

                if httpResponse.statusCode != 200 {
                    status.error = .httpError(httpResponse.statusCode)
                    return ([], status)
                }
            }

            let message: TransitRealtime_FeedMessage
            do {
                message = try TransitRealtime_FeedMessage(serializedBytes: data)
            } catch {
                print("[VehiclesVM] \(agencyID): ERROR - Decoding failed: \(error.localizedDescription)")
                status.error = .decodingError(error)
                return ([], status)
            }

            let totalEntities = message.entity.count
            let vehicleEntities = message.entity.filter { $0.hasVehicle }
            let withPosition = message.entity.filter { $0.hasVehicle && $0.vehicle.hasPosition }

            print("[VehiclesVM] \(agencyID): \(totalEntities) entities, \(vehicleEntities.count) vehicles, \(withPosition.count) with position")
            print("[VehiclesVM] \(agencyID): \(withPosition.count) vehicles")

            let vehicles = withPosition.map { RealtimeVehicle(from: $0, agency: agency) }
            status.vehicleCount = vehicles.count
            return (vehicles, status)
        } catch {
            print("[VehiclesVM] \(agencyName) (Agency ID \(agencyID))")
            print("[VehiclesVM] \(agencyID): ERROR - Network: \(error.localizedDescription)")
            status.lastFetchedAt = Date()
            status.error = .networkError(error)
            return ([], status)
        }
    }
}
