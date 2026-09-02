//
//  BookmarkActionsTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import UIKit
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class BookmarkActionsTests: OBATestCase {

    private var queue: OperationQueue!

    override init() async throws {
        try await super.init()

        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    private static let seedEpoch = Date(timeIntervalSince1970: 1_700_000_000)

    @MainActor
    private func makeTripBookmark(application: Application) throws -> Bookmark {
        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_10914.json"
        )
        let arrivalDeparture = try #require(stopArrivals.arrivalsAndDepartures.first)
        let bookmark = Bookmark(
            name: "Trip Bookmark",
            regionIdentifier: Fixtures.pugetSoundRegion.regionIdentifier,
            arrivalDeparture: arrivalDeparture,
            dateCreated: Self.seedEpoch
        )
        application.userDataStore.add(bookmark, to: nil)
        return bookmark
    }

    @MainActor
    private func makeStopBookmark(application: Application) throws -> Bookmark {
        let stops = try Fixtures.loadSomeStops()
        let stop = try #require(stops.first)
        let bookmark = Bookmark(
            name: "Stop Bookmark",
            regionIdentifier: Fixtures.pugetSoundRegion.regionIdentifier,
            stop: stop,
            dateCreated: Self.seedEpoch
        )
        application.userDataStore.add(bookmark, to: nil)
        return bookmark
    }

    /// Deleting a trip bookmark reports the unstar event, with the route and
    /// stop the user actually removed.
    @Test @MainActor func `Reporting a deletion emits the unstar event`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let analytics = try #require(application.analytics as? AnalyticsMock)
        let bookmark = try makeTripBookmark(application: application)

        BookmarkActions(application: application).reportDeletion(of: bookmark)

        let event = try #require(analytics.reportedEvents.last)
        #expect(event.label == AnalyticsLabels.removeBookmark)
    }

    /// A stop bookmark has no route or headsign, so there is no unstar event to
    /// report — matching the tab, which guards on both being present.
    @Test @MainActor func `Reporting a stop bookmark deletion emits nothing`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let analytics = try #require(application.analytics as? AnalyticsMock)
        let bookmark = try makeStopBookmark(application: application)
        let before = analytics.reportedEvents.count

        BookmarkActions(application: application).reportDeletion(of: bookmark)

        #expect(analytics.reportedEvents.count == before)
    }

    /// The identity keys fall back to the bookmark's own name and an empty
    /// headsign, so a bookmark missing route metadata still compares equal to
    /// the activity started from it.
    @Test @MainActor func `Live activity keys fall back to the bookmark name`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let bookmark = try makeStopBookmark(application: application)

        let keys = BookmarkActions.liveActivityKeys(for: bookmark)

        #expect(keys.routeShortName == bookmark.routeShortName ?? bookmark.name)
        #expect(keys.routeHeadsign == (bookmark.tripHeadsign ?? ""))
    }

    /// No arrivals means no content state, which is what makes `startLiveActivity`
    /// report failure instead of requesting an empty activity.
    @Test @MainActor func `Content state is nil without arrivals`() {
        #expect(BookmarkActions.buildContentState(from: []) == nil)
    }

    /// With arrivals, at most the first three are carried into the activity.
    @Test @MainActor func `Content state carries at most three arrivals`() throws {
        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals_and_departures_for_stop_1_29261.json"
        )
        try #require(stopArrivals.arrivalsAndDepartures.count >= 3)

        let state = try #require(BookmarkActions.buildContentState(from: stopArrivals.arrivalsAndDepartures))

        #expect(state.arrivals.count == 3)
    }

    /// Transit-center case (#1326): the same route serves both directions at one
    /// stop. Filtering on route ID alone would pick the opposite-direction bus
    /// because it leaves sooner. Chips and the headline countdown must follow
    /// the tracked destination, same key as trip bookmarks.
    @Test @MainActor func `Content state matching a departure drops the opposite direction`() throws {
        let oppositeSooner = try arrivalDeparture(
            routeID: "40_100479",
            headsign: "Angle Lake",
            tripID: "trip_south",
            departureEpoch: 1_700_000_120
        )
        let tracked = try arrivalDeparture(
            routeID: "40_100479",
            headsign: "Lynnwood City Center",
            tripID: "trip_north",
            departureEpoch: 1_700_000_480
        )
        let laterSameDirection = try arrivalDeparture(
            routeID: "40_100479",
            headsign: "Lynnwood City Center",
            tripID: "trip_north_2",
            departureEpoch: 1_700_000_840
        )

        let state = try #require(BookmarkActions.buildContentState(
            from: [oppositeSooner, tracked, laterSameDirection],
            matching: tracked
        ))

        #expect(state.arrivals.count == 2)
        #expect(state.arrivals.map(\.departureTime) == [
            Int(tracked.arrivalDepartureDate.timeIntervalSince1970),
            Int(laterSameDirection.arrivalDepartureDate.timeIntervalSince1970)
        ])
        #expect(!state.arrivals.map(\.departureTime).contains(Int(oppositeSooner.arrivalDepartureDate.timeIntervalSince1970)))
    }

    /// If the stop list is stale and no longer contains the tapped trip, still
    /// start an activity for that trip rather than failing or picking a stranger.
    @Test @MainActor func `Content state matching falls back to the selected departure`() throws {
        let tracked = try arrivalDeparture(
            routeID: "40_100479",
            headsign: "Lynnwood City Center",
            tripID: "trip_north",
            departureEpoch: 1_700_000_480
        )
        let otherRoute = try arrivalDeparture(
            routeID: "1_100002",
            headsign: "Downtown Seattle",
            tripID: "trip_other",
            departureEpoch: 1_700_000_100
        )

        let state = try #require(BookmarkActions.buildContentState(
            from: [otherRoute],
            matching: tracked
        ))

        #expect(state.arrivals.count == 1)
        #expect(state.arrivals[0].departureTime == Int(tracked.arrivalDepartureDate.timeIntervalSince1970))
    }

    /// Tracking a bookmark with no loaded arrivals can't build a content state,
    /// so it reports failure rather than requesting a contentless activity.
    @Test @MainActor func `Tracking without arrivals fails`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let bookmark = try makeTripBookmark(application: application)

        let result = BookmarkActions(application: application)
            .startLiveActivity(for: bookmark, arrivalDepartures: [])

        #expect(result == .failed)
    }

    /// Cancelling the editor must reach the delegate.
    ///
    /// `EditBookmarkViewController.close()` used to call `dismiss(animated:)`
    /// itself and tell nobody. The UIKit callers never noticed — their
    /// `bookmarkEditorCancelled` only dismisses, which UIKit had already done —
    /// but a presenter holding its own state, like the Bookmarks index sheet's
    /// `.sheet(item:)` binding, was left believing the editor was still up.
    @Test @MainActor func `Cancelling the bookmark editor notifies the delegate`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let bookmark = try makeStopBookmark(application: application)
        let delegate = BookmarkEditorDelegateSpy()

        let navigation = BookmarkActions(application: application)
            .makeBookmarkEditor(for: bookmark, delegate: delegate)
        let editor = try #require(navigation.viewControllers.first)

        // Fires the Cancel button's action rather than calling `close()`, which
        // is private — and this way the button's wiring is under test too.
        let cancelButton = try #require(editor.navigationItem.leftBarButtonItem)
        let action = try #require(cancelButton.action)
        let target = try #require(cancelButton.target as? NSObject)
        _ = target.perform(action, with: cancelButton)

        #expect(delegate.cancelledCount == 1)
        #expect(delegate.editedCount == 0)
    }

    /// Minimal `ArrivalDeparture` for Live Activity content-state tests. Times are
    /// JSON numbers; `JSONDecoder`'s default Date strategy is seconds-since-2001,
    /// which is fine — we compare through `arrivalDepartureDate`, not the raw ints.
    private func arrivalDeparture(
        routeID: String,
        headsign: String,
        tripID: String,
        departureEpoch: Int
    ) throws -> ArrivalDeparture {
        try Fixtures.dictionaryToModel(type: ArrivalDeparture.self, dictionary: [
            "arrivalEnabled": true,
            "blockTripSequence": 1,
            "departureEnabled": true,
            "distanceFromStop": 100.0,
            "lastUpdateTime": departureEpoch,
            "numberOfStopsAway": 1,
            "predicted": true,
            "predictedArrivalTime": departureEpoch,
            "predictedDepartureTime": departureEpoch,
            "routeId": routeID,
            "routeShortName": "1 Line",
            "scheduledArrivalTime": departureEpoch,
            "scheduledDepartureTime": departureEpoch,
            "serviceDate": departureEpoch,
            "situationIds": [] as [String],
            "status": "default",
            "stopId": "1_mtc",
            "stopSequence": 10,
            "totalStopsInTrip": 20,
            "tripHeadsign": headsign,
            "tripId": tripID,
            "vehicleId": "vehicle_\(tripID)"
        ])
    }
}

/// Records which `BookmarkEditorDelegate` callback the editor reached.
@MainActor
private final class BookmarkEditorDelegateSpy: NSObject, BookmarkEditorDelegate {
    private(set) var cancelledCount = 0
    private(set) var editedCount = 0

    func bookmarkEditorCancelled(_ viewController: UIViewController) {
        cancelledCount += 1
    }

    func bookmarkEditor(_ viewController: UIViewController, editedBookmark bookmark: Bookmark, isNewBookmark: Bool) {
        editedCount += 1
    }
}
