//
//  BookmarkDataLoaderTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class BookmarkDataLoaderTests: OBATestCase {

    private var queue: OperationQueue!

    override init() async throws {
        try await super.init()

        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    /// Thread-safe counter for tracking request counts.
    private final class RequestCounter {
        private let lock = NSLock()
        nonisolated(unsafe) private(set) var count: Int = 0

        nonisolated func increment() {
            lock.lock()
            defer { lock.unlock() }
            count += 1
        }
    }

    /// Counts arrivals requests so the scoped-provider test can assert the
    /// loader fetched only the bookmarks it was handed.
    @MainActor
    private final class RecordingDelegate: NSObject, BookmarkDataDelegate {
        var updateCount = 0
        func dataLoaderDidUpdate(_ dataLoader: BookmarkDataLoader) { updateCount += 1 }
    }

    /// Builds real *trip* bookmarks — `isTripBookmark` requires a route short
    /// name, route id, and trip headsign, which only a decoded `ArrivalDeparture`
    /// supplies. A bookmark that isn't a trip bookmark is skipped by the loader
    /// without a request, which would silently zero out the counts below.
    @MainActor
    private func makeTripBookmarks(count: Int, application: Application) throws -> [Bookmark] {
        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_10914.json"
        )
        let arrivalDeparture = try #require(stopArrivals.arrivalsAndDepartures.first)

        return (0..<count).map { index in
            let bookmark = Bookmark(
                name: "Bookmark \(index)",
                regionIdentifier: pugetSoundRegionIdentifier,
                arrivalDeparture: arrivalDeparture
            )
            bookmark.sortOrder = index
            application.userDataStore.add(bookmark, to: nil)
            return bookmark
        }
    }

    /// The provider — not the whole store — decides what gets fetched.
    @Test @MainActor
    func `Bookmark provider scopes fetches to the supplied bookmarks`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        let requestCounter = RequestCounter()
        dataLoader.mock(data: Fixtures.loadData(file: "arrivals-and-departures-for-stop-1_75414.json")) { request in
            let matches = request.url?.path.contains("/api/where/arrivals-and-departures-for-stop") ?? false
            if matches { requestCounter.increment() }
            return matches
        }

        let all = try makeTripBookmarks(count: 6, application: application)
        let scoped = Array(all.prefix(2))

        let delegate = RecordingDelegate()
        let loader = BookmarkDataLoader(
            application: application,
            delegate: delegate,
            bookmarkProvider: { scoped },
            autoRefreshes: false
        )

        await loader.loadDataAndWait()

        // Six bookmarks exist; only the two handed to the provider are fetched.
        #expect(requestCounter.count == 2)
    }

    /// With auto-refresh off, the loader installs no repeating timer.
    @Test @MainActor
    func `Auto refresh disabled installs no timer`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        dataLoader.mock(data: Fixtures.loadData(file: "arrivals-and-departures-for-stop-1_75414.json")) { request in
            request.url?.path.contains("/api/where/arrivals-and-departures-for-stop") ?? false
        }

        let bookmarks = try makeTripBookmarks(count: 1, application: application)
        let delegate = RecordingDelegate()
        let loader = BookmarkDataLoader(
            application: application,
            delegate: delegate,
            bookmarkProvider: { bookmarks },
            autoRefreshes: false
        )

        await loader.loadDataAndWait()

        #expect(loader.hasScheduledRefresh == false)
    }

    /// The Bookmarks tab's construction is untouched: every region bookmark is
    /// fetched and the repeating timer is installed.
    @Test @MainActor
    func `Default initializer fetches all region bookmarks and schedules refresh`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        let requestCounter = RequestCounter()
        dataLoader.mock(data: Fixtures.loadData(file: "arrivals-and-departures-for-stop-1_75414.json")) { request in
            let matches = request.url?.path.contains("/api/where/arrivals-and-departures-for-stop") ?? false
            if matches { requestCounter.increment() }
            return matches
        }

        _ = try makeTripBookmarks(count: 3, application: application)

        let delegate = RecordingDelegate()
        let loader = BookmarkDataLoader(application: application, delegate: delegate)

        await loader.loadDataAndWait()

        #expect(requestCounter.count == 3)
        #expect(loader.hasScheduledRefresh)

        loader.cancelUpdates()
    }
}
