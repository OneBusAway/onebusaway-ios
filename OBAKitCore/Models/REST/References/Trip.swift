//
//  Trip.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

public struct Trip: Identifiable, Codable, Hashable {
    /// The block_id field identifies the block to which the trip belongs.
    ///
    /// A block consists of a single trip or many sequential trips made using
    /// the same vehicle, defined by shared service day and block_id. A block_id
    /// an have trips with different service days, making distinct blocks.
    public let blockID: String

    /// The direction field contains a binary value that indicates the direction
    /// of travel for a trip.
    ///
    /// Use this field to distinguish between bi-directional trips with the same
    /// `route_id`. This field is not used in routing; it provides a way to
    /// separate trips by direction when publishing time tables. You can
    /// specify names for each direction with the `trip_headsign` field.
    public let direction: String?

    /// The id field contains an ID that identifies a trip. The trip id is dataset unique.
    public let id: String

    /// The route_id field contains an ID that uniquely identifies a route.
    public let routeID: String

    public let routeShortName: String?

    /// The service_id contains an ID that uniquely identifies a set of dates when
    /// service is available for one or more routes. This value is referenced from
    /// the calendar.txt or calendar_dates.txt file.
    public let serviceID: String

    /// The shape_id field contains an ID that defines a shape for the trip.
    /// This value is referenced from the shapes API.
    public let shapeID: String

    public let timeZone: String?

    /// Contains the text that appears in schedules and sign boards to identify the trip to passengers.
    ///
    /// For example: to identify train numbers for commuter rail trips. If riders do not commonly
    /// rely on trip names, this field may be blank. A short name, if provided, should uniquely
    /// identify a trip within a service day; it should not be used for destination names or
    /// limited/express designations.
    public let shortName: String?

    /// Contains the text that appears on a sign that identifies the trip's destination to passengers.
    ///
    /// Use this field to distinguish between different patterns of service in the same route.
    public let headsign: String?

    internal enum CodingKeys: String, CodingKey {
        case blockID = "blockId"
        case direction
        case headsign = "tripHeadsign"
        case id
        case routeID = "routeId"
        case routeShortName
        case serviceID = "serviceId"
        case shapeID = "shapeId"
        case shortName = "tripShortName"
        case timeZone
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        blockID = try container.decode(String.self, forKey: .blockID)
        direction = try? container.decodeIfPresent(String.self, forKey: .direction)
        headsign = try? container.decodeIfPresent(String.self, forKey: .headsign)
        id = try container.decode(String.self, forKey: .id)
        routeID = try container.decode(String.self, forKey: .routeID)
        routeShortName = String.nilifyBlankValue(try container.decodeIfPresent(String.self, forKey: .routeShortName))
        serviceID = try container.decode(String.self, forKey: .serviceID)
        shapeID = try container.decode(String.self, forKey: .shapeID)
        shortName = String.nilifyBlankValue(try container.decodeIfPresent(String.self, forKey: .shortName))
        timeZone = String.nilifyBlankValue(try container.decodeIfPresent(String.self, forKey: .timeZone))
    }
}
