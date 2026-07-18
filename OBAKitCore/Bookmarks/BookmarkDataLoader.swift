//
//  BookmarkDataLoader.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

@MainActor
public protocol BookmarkDataDelegate: NSObjectProtocol {
    func dataLoaderDidUpdate(_ dataLoader: BookmarkDataLoader)
    func dataLoader(_ dataLoader: BookmarkDataLoader, isLoadingChanged isLoading: Bool)
}

public extension BookmarkDataDelegate {
    func dataLoader(_ dataLoader: BookmarkDataLoader, isLoadingChanged isLoading: Bool) {}
}

/// Loads `[ArrivalDeparture]`s every 30 seconds for the list of provided `Bookmark`s.
@MainActor
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

    /// `true` if any per-bookmark fetch in the most-recently-completed batch failed.
    /// Reset to `false` at the start of each batch. Consumers read this when `isLoading`
    /// transitions to `false` to decide success vs. failure feedback (e.g. haptics).
    @MainActor public private(set) var lastBatchHadError: Bool = false

    /// Callers suspended in `loadDataAndWait()`, keyed by the batch they started.
    /// Resumed when that batch drains (`taskFinished`) or is retired (`cancelUpdates`).
    @MainActor private var batchContinuations: [UInt64: [CheckedContinuation<Void, Never>]] = [:]

    /// Stops whose arrival fetch has completed successfully at least once this
    /// session. Lets consumers distinguish "still loading" from "loaded, but no
    /// upcoming departures".
    @MainActor private var fetchedStopIDs = Set<StopID>()

    /// `true` once at least one arrival fetch for `stopID` has completed
    /// successfully this session.
    @MainActor public func hasFetchedData(forStopID stopID: StopID) -> Bool {
        fetchedStopIDs.contains(stopID)
    }

    public init(application: CoreApplication, delegate: BookmarkDataDelegate) {
        self.application = application
        self.delegate = delegate
    }

    public func startRefreshTimer() {
        timer?.invalidate()

        timer = Timer.scheduledMainActorTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] in
            self?.loadData()
        }
    }

    public func cancelUpdates() {
        timer?.invalidate()
        // Retire the current batch so any in-flight per-bookmark Task completions
        // (success or failure) see the mismatch and no-op. Used by deactivate/deinit paths.
        // Deliberately captures self strongly: the cleanup below must run even if the
        // owner released us, or suspended loadDataAndWait() callers would leak.
        Task { @MainActor in
            self.currentBatchID &+= 1
            // Retired fetches will never call taskFinished, so close out the
            // batch here — otherwise `isLoading` stays true forever and anyone
            // awaiting the batch boundary (e.g. pull-to-refresh) hangs.
            self.pendingFetchCount = 0
            if self.isLoading {
                self.isLoading = false
                self.delegate?.dataLoader(self, isLoadingChanged: false)
            }
            let continuations = self.batchContinuations.values.flatMap { $0 }
            self.batchContinuations.removeAll()
            continuations.forEach { $0.resume() }
        }
    }

    public func loadData() {
        timer?.invalidate()  // retire the timer inline; no separate main-actor hop needed
        let bookmarks = eligibleBookmarks()
        // Retiring the old batch (ID advance) and starting the new one happen in a single
        // main-actor Task, so there's no FIFO dependency between two independent Tasks.
        Task { @MainActor in
            self.startBatch(bookmarks: bookmarks, continuation: nil)
        }
        startRefreshTimer()
    }

    /// Starts a refresh batch and suspends until *that specific batch* drains
    /// (or is retired by `cancelUpdates()`). Unlike observing `isLoading`, this
    /// cannot be satisfied by the completion of a previously in-flight batch.
    public func loadDataAndWait() async {
        timer?.invalidate()
        let bookmarks = eligibleBookmarks()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Task { @MainActor in
                self.startBatch(bookmarks: bookmarks, continuation: continuation)
            }
        }
        startRefreshTimer()
    }

    private func eligibleBookmarks() -> [Bookmark] {
        application.userDataStore.bookmarks.filter {
            $0.regionIdentifier == application.regionsService.currentRegion?.id
        }
    }

    @MainActor private func startBatch(bookmarks: [Bookmark], continuation: CheckedContinuation<Void, Never>?) {
        currentBatchID &+= 1
        let batchID = currentBatchID
        beginBatch(count: bookmarks.count)
        if let continuation {
            if bookmarks.isEmpty {
                continuation.resume()
            } else {
                batchContinuations[batchID, default: []].append(continuation)
            }
        }
        for bookmark in bookmarks {
            loadData(bookmark: bookmark, batchID: batchID)
        }
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
                    // Skip stale completions: a newer batch has already started, so
                    // writing this fetch's data would overwrite fresher results and
                    // fire dataLoaderDidUpdate with stale state for the consumer.
                    guard batchID == self.currentBatchID else { return }

                    self.fetchedStopIDs.insert(bookmark.stopID)

                    let keysAndDeps = stopArrivals.arrivalsAndDepartures.tripKeyGroupedElements
                    for (key, deps) in keysAndDeps {
                        self.tripBookmarkKeys[key] = deps
                    }

                    self.delegate?.dataLoaderDidUpdate(self)
                }
            } catch {
                // Same staleness gate as the success path: if cancelUpdates() retired
                // the batch (or a newer batch started) while this fetch was in flight,
                // suppress the error — the consumer has moved on and shouldn't see it.
                let isCurrent = await MainActor.run { () -> Bool in
                    let current = batchID == self.currentBatchID
                    // Record the failure against the live batch so the batch-complete
                    // signal can report whether any fetch errored.
                    if current { self.lastBatchHadError = true }
                    return current
                }
                guard isCurrent else { return }
                await self.application.displayError(error)
            }
        }
    }

    @MainActor private func beginBatch(count: Int) {
        lastBatchHadError = false
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
        if pendingFetchCount == 0 {
            // Flip isLoading (and notify) before resuming awaiters, so anything
            // they read post-await (e.g. lastBatchHadError) is already current.
            if isLoading {
                isLoading = false
                delegate?.dataLoader(self, isLoadingChanged: false)
            }
            if let continuations = batchContinuations.removeValue(forKey: batchID) {
                continuations.forEach { $0.resume() }
            }
        }
    }

    public func dataForKey(_ key: TripBookmarkKey) -> [ArrivalDeparture] {
        tripBookmarkKeys[key, default: []]
    }

    /// A dictionary that maps each bookmark to `ArrivalDeparture`s.
    /// This is used to update the UI when new `ArrivalDeparture` objects are loaded.
    private var tripBookmarkKeys = [TripBookmarkKey: [ArrivalDeparture]]()
}
