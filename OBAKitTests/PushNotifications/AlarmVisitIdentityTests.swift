//
//  AlarmVisitIdentityTests.swift
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

/// `AlarmVisitIdentity.alarm(for:regionID:in:)` is how the stop page and the
/// trip page decide a departure already has an alarm, and so whether its row
/// offers "Set an alarm" or the existing one.
@MainActor
@Suite(.serialized)
struct AlarmVisitIdentityTests {

    private let regionID = 1

    /// A departure on `stop_1`, trip `trip_1`, stop sequence 5.
    private func departure() throws -> ArrivalDeparture {
        try Fixtures.arrivalDeparture(stopSequence: 5, stopID: "stop_1", tripID: "trip_1", vehicleID: "vehicle_1")
    }

    /// An alarm armed on a visit. Defaults match `departure()`; each test
    /// changes only what it is about.
    private func alarm(
        id: String,
        regionID: Int? = nil,
        stopID: StopID = "stop_1",
        tripID: String = "trip_1",
        serviceDate: Date? = nil,
        stopSequence: Int = 5,
        vehicleID: String? = "vehicle_1",
        title: String = "Route 1 to Downtown"
    ) throws -> Alarm {
        let alarm = try Fixtures.loadAlarm(id: id)
        alarm.deepLink = ArrivalDepartureDeepLink(
            title: title,
            regionID: regionID ?? self.regionID,
            stopID: stopID,
            tripID: tripID,
            serviceDate: try serviceDate ?? departure().serviceDate,
            stopSequence: stopSequence,
            vehicleID: vehicleID
        )
        return alarm
    }

    @Test func `An alarm armed on the same visit is found`() throws {
        let other = try alarm(id: "other", stopID: "stop_2")
        let match = try alarm(id: "match")

        let found = AlarmVisitIdentity.alarm(for: try departure(), regionID: regionID, in: [other, match])

        #expect(found === match)
    }

    /// The feed assigns a coach, and the deep link's title can change, once a
    /// scheduled trip goes real-time. Matching on either would show "Set an
    /// alarm" again and let the rider arm a second alarm on the same departure.
    @Test func `The vehicle and title don't affect the match`() throws {
        let scheduled = try alarm(id: "scheduled", vehicleID: nil, title: "Earlier title")

        let found = AlarmVisitIdentity.alarm(for: try departure(), regionID: regionID, in: [scheduled])

        #expect(found === scheduled)
    }

    enum Difference: String, CaseIterable, CustomTestStringConvertible {
        case region, stop, trip, serviceDate, stopSequence
        var testDescription: String { rawValue }
    }

    /// Each field on its own must be enough to tell two visits apart.
    @Test(arguments: Difference.allCases)
    func `An alarm on a different visit isn't found`(_ difference: Difference) throws {
        let serviceDate = try departure().serviceDate
        let differing: Alarm = switch difference {
        case .region: try alarm(id: "a", regionID: 2)
        case .stop: try alarm(id: "a", stopID: "stop_2")
        case .trip: try alarm(id: "a", tripID: "trip_2")
        case .serviceDate: try alarm(id: "a", serviceDate: serviceDate.addingTimeInterval(86_400))
        case .stopSequence: try alarm(id: "a", stopSequence: 6)
        }

        #expect(AlarmVisitIdentity.alarm(for: try departure(), regionID: regionID, in: [differing]) == nil)
    }

    /// The region comes from the caller, not the departure, so the same
    /// departure in another region is another visit.
    @Test func `The region passed in is the one matched`() throws {
        let match = try alarm(id: "match")

        #expect(AlarmVisitIdentity.alarm(for: try departure(), regionID: 2, in: [match]) == nil)
        #expect(AlarmVisitIdentity.alarm(for: try departure(), regionID: regionID, in: [match]) === match)
    }

    /// An alarm decoded without a deep link has no visit to compare.
    @Test func `An alarm without a deep link is skipped`() throws {
        let unlinked = try alarm(id: "unlinked")
        unlinked.deepLink = nil
        let match = try alarm(id: "match")

        #expect(AlarmVisitIdentity.alarm(for: try departure(), regionID: regionID, in: [unlinked]) == nil)
        #expect(AlarmVisitIdentity.alarm(for: try departure(), regionID: regionID, in: [unlinked, match]) === match)
    }

    /// The stop page builds identities from stored deep links and looks them up
    /// by the departure's, so the two initializers must agree.
    @Test func `A deep link and its departure make the same identity`() throws {
        let deepLink = try #require(try alarm(id: "a").deepLink)

        #expect(AlarmVisitIdentity(deepLink) == AlarmVisitIdentity(try departure(), regionID: regionID))
        #expect(AlarmVisitIdentity(deepLink).hashValue == AlarmVisitIdentity(try departure(), regionID: regionID).hashValue)
    }

    /// `OBALoc` falls back to its English literal, so read `en.lproj` directly
    /// to catch a missing key.
    @Test func `The removed announcement has an English string`() throws {
        let english = try #require(Bundle.obaKit.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:)))
        #expect(english.localizedString(forKey: "alarms.a11y_removed", value: "MISSING", table: nil) == "Alarm removed")
    }
}
