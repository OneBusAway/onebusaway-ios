//
//  TripPageAlarmTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
import UIKit
import OBAKitCore
@testable import OBAKit

/// The trip page always said "Add alarm", even with one set, so activating it
/// again made a second alarm, and the first couldn't be removed from here.
@MainActor
@Suite(.serialized)
final class TripPageAlarmTests: OBATestCase {

    private func makeApplication() -> Application {
        let app = buildApplication(queue: OperationQueue(), dataLoader: MockDataLoader(testName: name))
        app.regionsService.currentRegion = Fixtures.pugetSoundRegion
        return app
    }

    private func addAlarm(for departure: ArrivalDeparture, in app: Application) throws {
        let region = try #require(app.currentRegion)
        let alarm = try Fixtures.loadAlarm()
        alarm.deepLink = ArrivalDepartureDeepLink(arrivalDeparture: departure, regionID: region.regionIdentifier)
        // In the future, so it isn't pruned as expired.
        alarm.set(tripDate: Date(timeIntervalSinceNow: 900), alarmOffset: 5)
        app.userDataStore.add(alarm: alarm)
    }

    @Test func `The alarm button knows when an alarm is set`() throws {
        let app = makeApplication()

        let before = try TripPageFixture.makeOnScreenPage(application: app)
        #expect(!before.rootView.hasAlarm)

        try addAlarm(for: try #require(before.viewModel.tripConvertible.arrivalDeparture), in: app)

        let after = try TripPageFixture.makeOnScreenPage(application: app)
        #expect(after.rootView.hasAlarm)
    }

    /// An alarm for some other departure isn't this one's.
    @Test func `An alarm for another departure doesn't count`() throws {
        let app = makeApplication()
        let other = try #require(Fixtures.loadRESTAPIPayload(type: StopArrivals.self, fileName: "arrivals-and-departures_1_1121.json").arrivalsAndDepartures.first)
        try addAlarm(for: other, in: app)

        let page = try TripPageFixture.makeOnScreenPage(application: app)
        #expect(!page.rootView.hasAlarm)
    }
}
