//
//  AlarmVisitIdentity.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// The trip visit an alarm was armed on. Deliberately narrower than
/// `ArrivalDepartureDeepLink`'s own equality, which also compares `vehicleID`
/// and `title`: both change the moment a scheduled trip goes real-time and the
/// feed assigns it a coach, which would drop a live alarm out of the index —
/// flipping the row back to "Set an alarm" and letting the rider arm a second,
/// uncancellable alarm on the same departure.
struct AlarmVisitIdentity: Hashable {
    let regionID: Int
    let stopID: StopID
    let tripID: TripIdentifier
    let serviceDate: Date
    let stopSequence: Int

    init(_ deepLink: ArrivalDepartureDeepLink) {
        self.regionID = deepLink.regionID
        self.stopID = deepLink.stopID
        self.tripID = deepLink.tripID
        self.serviceDate = deepLink.serviceDate
        self.stopSequence = deepLink.stopSequence
    }

    /// Read straight from the departure rather than through a deep link, whose
    /// title reads the route and trip references, which trap until loaded.
    init(_ departure: ArrivalDeparture, regionID: Int) {
        self.regionID = regionID
        self.stopID = departure.stopID
        self.tripID = departure.tripID
        self.serviceDate = departure.serviceDate
        self.stopSequence = departure.stopSequence
    }

    /// The stored alarm armed on `departure`'s visit, if there is one.
    static func alarm(for departure: ArrivalDeparture, regionID: Int, in alarms: [Alarm]) -> Alarm? {
        let visit = AlarmVisitIdentity(departure, regionID: regionID)
        return alarms.first { $0.deepLink.map(AlarmVisitIdentity.init) == visit }
    }

    /// Spoken once an alarm is cancelled, which otherwise happens silently.
    static let removedAnnouncement = OBALoc("alarms.a11y_removed", value: "Alarm removed", comment: "VoiceOver announcement after the rider removes a departure alarm.")
}
