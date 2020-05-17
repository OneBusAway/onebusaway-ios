//
//  Alarm.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/10/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
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
        return
            url == rhs.url &&
            deepLink == rhs.deepLink &&
            tripDate == rhs.tripDate &&
            alarmDate == rhs.alarmDate
    }

    override public var hash: Int {
        var hasher = Hasher()
        hasher.combine(url)
        hasher.combine(deepLink)
        hasher.combine(tripDate)
        hasher.combine(alarmDate)
        return hasher.finalize()
    }

    public func set(tripDate: Date, alarmOffset minutes: Int) {
        self.tripDate = tripDate
        self.alarmDate = tripDate.addingTimeInterval(TimeInterval(abs(minutes) * -60))
    }
}
