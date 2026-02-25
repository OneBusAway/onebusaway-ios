//
//  StopsViewModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MapKit
import OBAKitCore

/// View model that manages stop loading for map views based on visible region
@MainActor
class StopsViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var stops: [Stop] = []
    @Published var isLoading = false

    // MARK: - Private Properties

    private let application: Application
    private var loadTask: Task<Void, Never>?

    // MARK: - Constants (matching MapRegionManager)

    /// Only load stops when the map is zoomed in enough (MKMapRect height threshold)
    private let requiredHeightToShowStops: Double = 40_000

    /// Load stops slightly beyond the visible region to reduce loading on small pans
    private let regionFudgeFactor: Double = 1.1

    /// Debounce interval to prevent excessive API calls during map panning
    private let debounceInterval: UInt64 = 250_000_000 // 0.25 seconds in nanoseconds

    // MARK: - Initialization

    init(application: Application) {
        self.application = application
    }

    // MARK: - Public Methods

    /// Called when the map region changes. Debounces and loads stops for the new region.
    /// - Parameter region: The current visible map region
    func regionDidChange(_ region: MKCoordinateRegion) {
        loadTask?.cancel()
        loadTask = Task {
            try? await Task.sleep(nanoseconds: debounceInterval)
            guard !Task.isCancelled else { return }
            await loadStops(for: region)
        }
    }

    // MARK: - Private Methods

    private func loadStops(for region: MKCoordinateRegion) async {
        // Check zoom level - clear stops if too zoomed out
        let mapRect = MKMapRect(region)
        guard mapRect.size.height <= requiredHeightToShowStops else {
            stops = []
            return
        }

        guard let apiService = application.apiService else { return }

        // Apply fudge factor to load slightly beyond visible area
        var expandedRegion = region
        expandedRegion.span.latitudeDelta *= regionFudgeFactor
        expandedRegion.span.longitudeDelta *= regionFudgeFactor

        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await apiService.getStops(region: expandedRegion)
            stops = response.list
        } catch {
            // Silently fail - stops are supplementary data
            // Could add error logging here if desired
        }
    }
}
