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

    /// Stops whose arrival fetch has finished this session — a successful
    /// payload, a literal HTTP 404, or HTTP 200 with body `null`. Lets
    /// consumers distinguish "still loading" from "loaded, but no upcoming
    /// departures". Empty HTTP 200 (also thrown as `APIError.requestNotFound`)
    /// is not recorded here.
    @MainActor private var fetchedStopIDs = Set<StopID>()

    /// `true` once an arrival fetch for `stopID` has finished this session
    /// (success, HTTP 404, or JSON `null`).
    @MainActor public func hasFetchedData(forStopID stopID: StopID) -> Bool {
        fetchedStopIDs.contains(stopID)
    }

    /// When set, supplies the bookmarks a batch should fetch instead of every
    /// bookmark in the current region. Lets a caller that only displays a few
    /// bookmarks — the home sheet's preview section — reuse this loader without
    /// paying for the whole set.
    private let bookmarkProvider: (() -> [Bookmark])?

    /// When `false`, `startRefreshTimer()` is a no-op, so the loader fetches
    /// only when explicitly asked. Callers that display a handful of bookmarks
    /// outside a dedicated screen don't want a background 30-second cycle.
    private let autoRefreshes: Bool

    public init(
        application: CoreApplication,
        delegate: BookmarkDataDelegate,
        bookmarkProvider: (() -> [Bookmark])? = nil,
        autoRefreshes: Bool = true
    ) {
        self.application = application
        self.delegate = delegate
        self.bookmarkProvider = bookmarkProvider
        self.autoRefreshes = autoRefreshes
    }

    public func startRefreshTimer() {
        timer?.invalidate()

        guard autoRefreshes else {
            timer = nil
            return
        }

        timer = Timer.scheduledMainActorTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] in
            self?.loadData()
        }
    }

    /// Whether a repeating refresh is currently armed.
    ///
    /// Deliberately `internal`, not `public`: nothing in the app reads it, and
    /// it exists so `BookmarkDataLoaderTests` can assert that a loader built with
    /// `autoRefreshes: false` really installs no timer. `@testable import` reaches
    /// it; the framework's public surface doesn't grow for a test.
    var hasScheduledRefresh: Bool {
        timer?.isValid ?? false
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
        if let bookmarkProvider {
            return bookmarkProvider()
        }
        return application.userDataStore.bookmarks.filter {
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

        // `beginBatch` reserved one slot per bookmark. Results arrive per *stop*
        // (the loader fetches each stop once), so count how many slots each stop
        // settles, and release at once the slots that will never fetch.
        var slotsByStop = [StopID: Int]()
        for bookmark in bookmarks {
            if application.apiService != nil, bookmark.isTripBookmark {
                slotsByStop[bookmark.stopID, default: 0] += 1
            } else {
                // No fetch will run for this bookmark — release the slot reserved by beginBatch.
                taskFinished(batchID: batchID)
            }
        }

        guard let apiService = application.apiService, !slotsByStop.isEmpty else { return }

        let slots = slotsByStop
        let requests = slots.keys.map { BookmarkArrivalsRequest(stopID: $0) }
        Task(priority: .userInitiated) {
            for await (stopID, result) in BookmarkArrivalsLoader().arrivals(for: requests, using: apiService) {
                // The loader only ever reports stops it was asked about, so a
                // miss here means the invariant broke. Settling 0 slots would
                // leave the batch short a release and hang `loadDataAndWait`
                // silently; say so in debug instead.
                guard let stopSlots = slots[stopID] else {
                    assertionFailure("BookmarkArrivalsLoader delivered a stop (\(stopID)) this batch never requested.")
                    continue
                }

                // One task per stop, so a slow `displayError` for one stop
                // does not hold up delivery of the next stop's arrivals.
                Task { @MainActor in
                    await self.settle(result, stopID: stopID, slots: stopSlots, batchID: batchID)
                }
            }
        }
    }

    /// Applies one stop's result, then releases the slots of every bookmark at
    /// that stop. The release comes last, as it did when this was a `defer`:
    /// `loadDataAndWait()` must not return before the delegate has been told.
    @MainActor
    private func settle(_ result: Result<[ArrivalDeparture], Error>, stopID: StopID, slots: Int, batchID: UInt64) async {
        defer {
            for _ in 0..<slots { taskFinished(batchID: batchID) }
        }

        // Skip stale completions: a newer batch has already started (or
        // cancelUpdates() retired this one), so writing this fetch's data would
        // overwrite fresher results, and an error would be shown to a consumer
        // that has moved on.
        guard batchID == currentBatchID else { return }

        switch result {
        case .success(let arrivals):
            fetchedStopIDs.insert(stopID)
            for (key, deps) in arrivals.tripKeyGroupedElements {
                tripBookmarkKeys[key] = deps
            }
            delegate?.dataLoaderDidUpdate(self)

        case .failure(let error as APIError) where error.indicatesMissingStop:
            // The stop no longer exists in this region. Don't bulletin —
            // settle the card on "No upcoming departures" and drop any
            // previous countdown for this stop.
            fetchedStopIDs.insert(stopID)
            tripBookmarkKeys = tripBookmarkKeys.filter { $0.key.stopID != stopID }
            delegate?.dataLoaderDidUpdate(self)

        case .failure(let error):
            // Record the failure against the live batch so the batch-complete
            // signal can report whether any fetch errored.
            lastBatchHadError = true
            await application.displayError(error)
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
