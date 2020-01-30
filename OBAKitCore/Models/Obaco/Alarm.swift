//
//  Alarm.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/10/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

public class Alarm: NSObject, Codable {
    public let url: URL
    public var deepLink: ArrivalDepartureDeepLink?

    private enum CodingKeys: String, CodingKey {
        case url, deepLink
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decode(URL.self, forKey: .url)
        deepLink = try container.decodeIfPresent(ArrivalDepartureDeepLink.self, forKey: .deepLink)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(url, forKey: .url)
        try container.encodeIfPresent(deepLink, forKey: .deepLink)
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let rhs = object as? Alarm else { return false }
        return
            url == rhs.url &&
            deepLink == rhs.deepLink
    }

    override public var hash: Int {
        var hasher = Hasher()
        hasher.combine(url)
        hasher.combine(deepLink)
        return hasher.finalize()
    }
}
