//
//  Trip.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 10/21/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

public class Trip: NSObject, Decodable, HasReferences {
    /// The block_id field identifies the block to which the trip belongs.
    ///
    /// A block consists of a single trip or many sequential trips made using
    /// the same vehicle, defined by shared service day and block_id. A block_id
    /// an have trips with different service days, making distinct blocks.
    public let blockID: String

    /// The direction field contains a binary value that indicates the direction
    // of travel for a trip. Use this field to distinguish between bi-directional
    // trips with the same route_id. This field is not used in routing; it provides
    // a way to separate trips by direction when publishing time tables. You can
    // specify names for each direction with the trip_headsign field.
    public let direction: String?

    /// The id field contains an ID that identifies a trip. The trip id is dataset unique.
    public let id: String

    /// The route_id field contains an ID that uniquely identifies a route.
    public let routeID: String

    /// The Route served by this trip.
    public var route: Route!

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
    public let headsign: String

    private enum CodingKeys: String, CodingKey {
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

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        blockID = try container.decode(String.self, forKey: .blockID)
        direction = try? container.decode(String.self, forKey: .direction)
        headsign = try container.decode(String.self, forKey: .headsign)
        id = try container.decode(String.self, forKey: .id)
        routeID = try container.decode(String.self, forKey: .routeID)
        routeShortName = ModelHelpers.nilifyBlankValue(try container.decode(String.self, forKey: .routeShortName))
        serviceID = try container.decode(String.self, forKey: .serviceID)
        shapeID = try container.decode(String.self, forKey: .shapeID)
        shortName = ModelHelpers.nilifyBlankValue(try container.decode(String.self, forKey: .shortName))
        timeZone = ModelHelpers.nilifyBlankValue(try container.decode(String.self, forKey: .timeZone))
    }

    // MARK: - HasReferences

    public func loadReferences(_ references: References) {
        route = references.routeWithID(routeID)
    }

    // MARK: - Route Descriptions

    /// A 'best effort' determination of the headsign for this `Trip`'s route.
    public var routeHeadsign: String {
        let bestShortName = routeShortName ?? route.shortName
        let headsign = self.headsign

        return "\(bestShortName) - \(headsign)"
    }

    // MARK: - Equality

    public override func isEqual(_ object: Any?) -> Bool {
        guard let rhs = object as? Trip else { return false }
        return
            blockID == rhs.blockID &&
            direction == rhs.direction &&
            headsign == rhs.headsign &&
            id == rhs.id &&
            routeID == rhs.routeID &&
            routeShortName == rhs.routeShortName &&
            serviceID == rhs.serviceID &&
            shapeID == rhs.shapeID &&
            shortName == rhs.shortName &&
            timeZone == rhs.timeZone
    }

    override public var hash: Int {
        var hasher = Hasher()
        hasher.combine(blockID)
        hasher.combine(direction)
        hasher.combine(headsign)
        hasher.combine(id)
        hasher.combine(routeID)
        hasher.combine(routeShortName)
        hasher.combine(serviceID)
        hasher.combine(shapeID)
        hasher.combine(shortName)
        hasher.combine(timeZone)
        return hasher.finalize()
    }
}
