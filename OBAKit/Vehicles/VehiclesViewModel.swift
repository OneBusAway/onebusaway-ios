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
    @Published var isLoading: Bool = false
    @Published var error: Error?
    @Published var lastUpdated: Date?
    @Published var cameraPosition: MapCameraPosition = .automatic

    // MARK: - Private Properties

    private let feedURL: URL
    private var refreshTask: Task<Void, Never>?

    /// Auto-refresh interval in seconds
    private let refreshInterval: TimeInterval = 30

    // MARK: - Initialization

    init(feedURL: URL = URL(string: "https://api.pugetsound.onebusaway.org/api/gtfs_realtime/vehicle-positions-for-agency/40.pb?key=org.onebusaway.iphone")!) {
        self.feedURL = feedURL
    }

    deinit {
        refreshTask?.cancel()
    }

    // MARK: - Public Methods

    /// Fetches vehicle positions from the feed
    func fetchVehicles() async {
        guard !isLoading else { return }

        isLoading = true
        error = nil

        do {
            let (data, _) = try await URLSession.shared.data(from: feedURL)
            let message = try TransitRealtime_FeedMessage(serializedBytes: data)

            self.vehicles = message.entity
                .filter { $0.hasVehicle && $0.vehicle.hasPosition }
                .map { RealtimeVehicle(from: $0) }
            self.lastUpdated = Date()
        } catch {
            self.error = error
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

    /// Centers the map on the Puget Sound region (default region for this feed)
    func centerOnDefaultRegion() {
        let pugetSoundCenter = CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)
        cameraPosition = .region(MKCoordinateRegion(
            center: pugetSoundCenter,
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
        ))
    }
}
