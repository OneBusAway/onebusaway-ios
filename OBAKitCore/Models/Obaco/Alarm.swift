//
//  Alarm.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// An alarm is a local representation of a push notification that will arrive to signal the user when it is time to depart to meet a transit vehicle. Part of the Obaco service.
public class Alarm: NSObject, Codable {
    public let url: URL
    public var deepLink: ArrivalDepartureDeepLink?
    public var tripDate: Date?
    public var alarmDate: Date?

    private enum CodingKeys: String, CodingKey {
        case url, deepLink, tripDate, alarmDate
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decode(URL.self, forKey: .url)
        deepLink = try container.decodeIfPresent(ArrivalDepartureDeepLink.self, forKey: .deepLink)

        if let timeInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .tripDate) {
            tripDate = Date(timeIntervalSince1970: timeInterval)
        }

        if let timeInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .alarmDate) {
            alarmDate = Date(timeIntervalSince1970: timeInterval)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(url, forKey: .url)
        try container.encodeIfPresent(deepLink, forKey: .deepLink)

        if let timeInterval = tripDate?.timeIntervalSince1970 {
            try container.encodeIfPresent(timeInterval, forKey: .tripDate)
        }

        if let timeInterval = alarmDate?.timeIntervalSince1970 {
            try container.encodeIfPresent(timeInterval, forKey: .alarmDate)
        }
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let rhs = object as? Alarm else { return false }
        // Compare dates via timeIntervalSince1970 so an in-memory alarm equals the same
        // alarm after a UserDefaults round-trip — `Date` carries sub-microsecond precision
        // that is lost on encode/decode (see init(from:) / encode(to:) above), so a raw
        // `==` would falsely report inequality for an alarm that was just persisted.
        return
            url == rhs.url &&
            deepLink == rhs.deepLink &&
            Alarm.datesEqual(tripDate, rhs.tripDate) &&
            Alarm.datesEqual(alarmDate, rhs.alarmDate)
    }

    private static func datesEqual(_ lhs: Date?, _ rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case let (l?, r?): return l.timeIntervalSince1970 == r.timeIntervalSince1970
        default: return false
        }
    }

    override public var hash: Int {
        var hasher = Hasher()
        hasher.combine(url)
        hasher.combine(deepLink)
        hasher.combine(tripDate?.timeIntervalSince1970)
        hasher.combine(alarmDate?.timeIntervalSince1970)
        return hasher.finalize()
    }

    public func set(tripDate: Date, alarmOffset minutes: Int) {
        self.tripDate = tripDate
        self.alarmDate = tripDate.addingTimeInterval(TimeInterval(abs(minutes) * -60))
    }
}
