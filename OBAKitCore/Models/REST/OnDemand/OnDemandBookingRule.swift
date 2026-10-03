//
//  OnDemandBookingRule.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// GTFS-Flex `booking_rules.txt` as the API exposes it (wiki §2.4). Nullable
/// conditionally-required fields do ship from real feeds; the evaluator
/// (spec §6.2) decides what each null means.
public struct OnDemandBookingRule: Decodable, Identifiable, Hashable, Sendable {
    public let id: String
    /// 0 real-time, 1 same-day, 2 prior-day(s).
    public let bookingType: Int
    /// Minutes. `bookingType` 1 only.
    public let priorNoticeDurationMin: Int?
    /// Minutes.
    public let priorNoticeDurationMax: Int?
    /// Days before travel. `bookingType` 2 only.
    public let priorNoticeLastDay: Int?
    public let priorNoticeLastTime: GTFSTimeOfDay?
    public let priorNoticeStartDay: Int?
    public let priorNoticeStartTime: GTFSTimeOfDay?
    /// Combined calendar ID whose service days `priorNoticeLastDay` and
    /// `priorNoticeStartDay` count (spec §6.1). `bookingType` 2 only.
    public let priorNoticeCalendarID: String?
    public let message: String?
    public let pickupMessage: String?
    public let dropOffMessage: String?
    /// As published in the feed, unformatted.
    public let phoneNumber: String?
    public let infoURL: URL?
    public let bookingURL: URL?

    private enum CodingKeys: String, CodingKey {
        case id, bookingType, priorNoticeDurationMin, priorNoticeDurationMax
        case priorNoticeLastDay, priorNoticeLastTime, priorNoticeStartDay, priorNoticeStartTime
        case priorNoticeCalendarID = "priorNoticeCalendarId"
        case message, pickupMessage, dropOffMessage, phoneNumber
        case infoURL = "infoUrl"
        case bookingURL = "bookingUrl"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        bookingType = try container.decode(Int.self, forKey: .bookingType)
        priorNoticeDurationMin = try container.decodeIfPresent(Int.self, forKey: .priorNoticeDurationMin)
        priorNoticeDurationMax = try container.decodeIfPresent(Int.self, forKey: .priorNoticeDurationMax)
        priorNoticeLastDay = try container.decodeIfPresent(Int.self, forKey: .priorNoticeLastDay)
        priorNoticeLastTime = try container.decodeIfPresent(GTFSTimeOfDay.self, forKey: .priorNoticeLastTime)
        priorNoticeStartDay = try container.decodeIfPresent(Int.self, forKey: .priorNoticeStartDay)
        priorNoticeStartTime = try container.decodeIfPresent(GTFSTimeOfDay.self, forKey: .priorNoticeStartTime)
        priorNoticeCalendarID = String.nilifyBlankValue(try container.decodeIfPresent(String.self, forKey: .priorNoticeCalendarID))
        message = String.nilifyBlankValue(try container.decodeIfPresent(String.self, forKey: .message))
        pickupMessage = String.nilifyBlankValue(try container.decodeIfPresent(String.self, forKey: .pickupMessage))
        dropOffMessage = String.nilifyBlankValue(try container.decodeIfPresent(String.self, forKey: .dropOffMessage))
        phoneNumber = String.nilifyBlankValue(try container.decodeIfPresent(String.self, forKey: .phoneNumber))
        infoURL = String.nilifyBlankValue(try container.decodeIfPresent(String.self, forKey: .infoURL)).flatMap(URL.init(string:))
        bookingURL = String.nilifyBlankValue(try container.decodeIfPresent(String.self, forKey: .bookingURL)).flatMap(URL.init(string:))
    }
}
