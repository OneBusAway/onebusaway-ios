//
//  BookmarksArrivalsViewModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// ViewModel that manages fetching and refreshing arrival data for bookmarks
@MainActor
class BookmarksArrivalsViewModel: ObservableObject {
    /// Arrival data grouped by TripBookmarkKey
    @Published private(set) var arrivalsData: [TripBookmarkKey: [ArrivalDeparture]] = [:]

    /// Whether data is currently being loaded
    @Published private(set) var isLoading = false

    private let application: Application
    private var refreshTask: Task<Void, Never>?

    init(application: Application) {
        self.application = application
    }

    deinit {
        refreshTask?.cancel()
    }

    /// Starts the automatic refresh cycle (loads immediately, then every 30 seconds)
    func startRefreshing() {
        guard refreshTask == nil else { return }

        refreshTask = Task {
            while !Task.isCancelled {
                await loadArrivals()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    /// Stops the automatic refresh cycle
    func stopRefreshing() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// Loads arrival data for all trip bookmarks in the current region
    func loadArrivals() async {
        guard let apiService = application.apiService,
              let region = application.currentRegion else {
            return
        }

        isLoading = true
        defer { isLoading = false }

        // Get trip bookmarks in the current region
        let bookmarks = application.userDataStore.findBookmarks(in: region)
            .filter { $0.isTripBookmark }

        // Get unique stop IDs to minimize API calls
        let uniqueStopIDs = Set(bookmarks.map { $0.stopID })

        guard !uniqueStopIDs.isEmpty else {
            arrivalsData = [:]
            return
        }

        // Fetch arrivals for each stop in parallel
        var newArrivalsData: [TripBookmarkKey: [ArrivalDeparture]] = [:]

        await withTaskGroup(of: (StopID, [ArrivalDeparture]?).self) { group in
            for stopID in uniqueStopIDs {
                group.addTask {
                    do {
                        let response = try await apiService.getArrivalsAndDeparturesForStop(
                            id: stopID,
                            minutesBefore: 0,
                            minutesAfter: 60
                        )
                        return (stopID, response.entry.arrivalsAndDepartures)
                    } catch {
                        return (stopID, nil)
                    }
                }
            }

            // Collect results and group by TripBookmarkKey
            for await (_, arrivals) in group {
                guard let arrivals else { continue }

                let groupedArrivals = arrivals.tripKeyGroupedElements
                for (key, deps) in groupedArrivals {
                    newArrivalsData[key] = deps
                }
            }
        }

        arrivalsData = newArrivalsData
    }

    /// Returns up to 3 arrivals for the given bookmark
    func arrivals(for bookmark: Bookmark) -> [ArrivalDeparture] {
        guard let key = TripBookmarkKey(bookmark: bookmark) else { return [] }
        return Array((arrivalsData[key] ?? []).prefix(3))
    }
}
