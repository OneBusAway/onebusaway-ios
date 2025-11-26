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

    // MARK: - Private Properties

    private let application: Application
    private var refreshTask: Task<Void, Never>?

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

            // 2. Fetch vehicles for all agencies concurrently
            typealias FetchResult = (vehicles: [RealtimeVehicle], status: AgencyFeedStatus)
            let results = await withTaskGroup(of: FetchResult.self) { group -> [FetchResult] in
                for agencyWithCoverage in agencies {
                    group.addTask {
                        await self.fetchVehiclesForAgency(
                            agencyWithCoverage.agencyID,
                            agencyName: agencyWithCoverage.agency?.name ?? "Unknown",
                            agency: agencyWithCoverage.agency
                        )
                    }
                }

                var results: [FetchResult] = []
                for await result in group {
                    results.append(result)
                }
                return results
            }

            self.vehicles = results.flatMap { $0.vehicles }
            self.feedStatuses = results.map { $0.status }.sorted { $0.agencyName < $1.agencyName }
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
