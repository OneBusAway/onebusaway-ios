//
//  BookmarkDataLoader.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

public protocol BookmarkDataDelegate: NSObjectProtocol {
    func dataLoaderDidUpdate(_ dataLoader: BookmarkDataLoader)
    func dataLoader(_ dataLoader: BookmarkDataLoader, isLoadingChanged isLoading: Bool)
}

public extension BookmarkDataDelegate {
    func dataLoader(_ dataLoader: BookmarkDataLoader, isLoadingChanged isLoading: Bool) {}
}

/// Loads `[ArrivalDeparture]`s every 30 seconds for the list of provided `Bookmark`s.
public class BookmarkDataLoader: NSObject {
    private let refreshInterval = 30.0

    private var timer: Timer?

    private let application: CoreApplication

    public weak var delegate: BookmarkDataDelegate?

    /// Number of per-bookmark fetches still outstanding in the current batch.
    /// Mutated only on the main actor.
    @MainActor private var pendingFetchCount: Int = 0

    /// Monotonically increasing batch identifier. Each `loadData()` call advances it,
    /// so per-fetch completion callbacks from a prior batch can identify themselves
    /// as stale and skip the count decrement.
    @MainActor private var currentBatchID: UInt64 = 0

    /// `true` while any per-bookmark fetch in the current batch is in flight.
    /// Drives spinner UI in consumers.
    @MainActor public private(set) var isLoading: Bool = false

    public init(application: CoreApplication, delegate: BookmarkDataDelegate) {
        self.application = application
        self.delegate = delegate
    }

    public func startRefreshTimer() {
        timer?.invalidate()

        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.loadData()
        }
    }

    public func cancelUpdates() {
        timer?.invalidate()

        for op in operations {
            op.cancel()
        }
    }

    private var operations = [Operation]()

    public func loadData() {
        cancelUpdates()
        let bookmarks = application.userDataStore.bookmarks.filter {
            $0.regionIdentifier == application.regionsService.currentRegion?.id
        }
        Task { @MainActor in
            self.currentBatchID &+= 1
            let batchID = self.currentBatchID
            self.beginBatch(count: bookmarks.count)
            for bookmark in bookmarks {
                self.loadData(bookmark: bookmark, batchID: batchID)
            }
        }
        startRefreshTimer()
    }

    @MainActor
    private func loadData(bookmark: Bookmark, batchID: UInt64) {
        guard
            let apiService = application.apiService,
            bookmark.isTripBookmark
        else {
            // No fetch will run for this bookmark — release the slot reserved by beginBatch.
            taskFinished(batchID: batchID)
            return
        }

        Task(priority: .userInitiated) {
            defer {
                Task { @MainActor in self.taskFinished(batchID: batchID) }
            }
            do {
                let stopArrivals = try await apiService.getArrivalsAndDeparturesForStop(id: bookmark.stopID, minutesBefore: 0, minutesAfter: 60).entry

                await MainActor.run {
                    let keysAndDeps = stopArrivals.arrivalsAndDepartures.tripKeyGroupedElements
                    for (key, deps) in keysAndDeps {
                        self.tripBookmarkKeys[key] = deps
                    }

                    self.delegate?.dataLoaderDidUpdate(self)
                }
            } catch {
                await self.application.displayError(error)
            }
        }
    }

    @MainActor private func beginBatch(count: Int) {
        pendingFetchCount = count
        let nowLoading = pendingFetchCount > 0
        if nowLoading != isLoading {
            isLoading = nowLoading
            delegate?.dataLoader(self, isLoadingChanged: nowLoading)
        } else if nowLoading == false {
            // Edge case: a batch with zero bookmarks. Notify so consumers can clear any
            // residual UI (e.g. a spinner that was started in anticipation of a pull).
            delegate?.dataLoader(self, isLoadingChanged: false)
        }
    }

    @MainActor private func taskFinished(batchID: UInt64) {
        // Stale completion from a prior batch — current batch's count is authoritative.
        guard batchID == currentBatchID, pendingFetchCount > 0 else { return }
        pendingFetchCount -= 1
        if pendingFetchCount == 0 && isLoading {
            isLoading = false
            delegate?.dataLoader(self, isLoadingChanged: false)
        }
    }

    public func dataForKey(_ key: TripBookmarkKey) -> [ArrivalDeparture] {
        tripBookmarkKeys[key, default: []]
    }

    /// A dictionary that maps each bookmark to `ArrivalDeparture`s.
    /// This is used to update the UI when new `ArrivalDeparture` objects are loaded.
    private var tripBookmarkKeys = [TripBookmarkKey: [ArrivalDeparture]]()
}
