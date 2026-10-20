//
//  ExternalNavigationHostTests.swift
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

/// Navigation that starts outside the visible UI (links, notifications, widgets)
/// goes to the map panel's sheets when the panel is the root, rather than to a
/// classic tab that isn't there.
@MainActor
@Suite(.serialized)
final class ExternalNavigationHostTests: OBATestCase {

    private final class RecordingHost: ExternalNavigationHost {
        var stops: [StopID] = []
        var trips: [(tripID: String, destinationStopID: StopID?)] = []
        var pages: [ClassicApplicationRootController.Page] = []

        func openStop(_ stopID: StopID) { stops.append(stopID) }
        func openTrip(_ arrivalDeparture: ArrivalDeparture, destinationStopID: StopID?) {
            trips.append((arrivalDeparture.tripID, destinationStopID))
        }
        func show(page: ClassicApplicationRootController.Page) { pages.append(page) }
    }

    private var queue: OperationQueue!
    private let navigationHost = RecordingHost()

    override init() async throws {
        try await super.init()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    private func makeApplication() -> Application {
        let app = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        app.externalNavigationHost = navigationHost
        return app
    }

    @Test func `A stop from outside goes to the panel`() {
        let app = makeApplication()

        let dismissing = app.pushStopFromOutside("1_75403")

        #expect(navigationHost.stops == ["1_75403"])
        #expect(!dismissing)
    }

    /// The cold-launch stash used to be cleared and then dropped in panel mode,
    /// so the tap that launched the app was lost for good.
    @Test func `A stop stashed on cold launch opens on the panel once its root loads`() {
        let app = makeApplication()
        app.pendingStopID = "1_75403"

        app.rootUserInterfaceDidLoad()

        #expect(navigationHost.stops == ["1_75403"])
        #expect(app.pendingStopID == nil)
    }

    @Test func `A trip from outside goes to the panel with its shared destination`() throws {
        let app = makeApplication()
        let arrival = try Fixtures.arrivalDeparture(tripID: "trip_42")

        app.openTripFromOutside(arrival, destinationStopID: "1_999")

        #expect(navigationHost.trips.map(\.tripID) == ["trip_42"])
        #expect(navigationHost.trips.first?.destinationStopID == "1_999")
    }

    @Test func `A tab asked for without a classic root goes to the panel`() {
        let app = makeApplication()
        #expect(app.viewRouter.rootController == nil)

        app.viewRouter.rootNavigateTo(page: .bookmarks)

        #expect(navigationHost.pages == [.bookmarks])
    }
}
