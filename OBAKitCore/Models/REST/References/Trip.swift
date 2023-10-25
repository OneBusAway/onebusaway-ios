//
//  Trip.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MetaCodable

@Codable
public struct Trip: Identifiable, Hashable {

    /// The id field contains an ID that identifies a trip. The trip id is dataset unique.
    public let id: String

    /// The block_id field identifies the block to which the trip belongs.
    ///
    /// A block consists of a single trip or many sequential trips made using
    /// the same vehicle, defined by shared service day and block_id. A block_id
    /// an have trips with different service days, making distinct blocks.
    @CodedAt("blockId")
    public let blockID: String

    /// The direction field contains a binary value that indicates the direction
    /// of travel for a trip.
    ///
    /// Use this field to distinguish between bi-directional trips with the same
    /// `route_id`. This field is not used in routing; it provides a way to
    /// separate trips by direction when publishing time tables. You can
    /// specify names for each direction with the `trip_headsign` field.
    public let direction: String?

    /// The route_id field contains an ID that uniquely identifies a route
    @CodedAt("routeId")
    public let routeID: String

    @CodedBy(String.NillifyEmptyString())
    public let routeShortName: String?

    /// The service_id contains an ID that uniquely identifies a set of dates when
    /// service is available for one or more routes. This value is referenced from
    /// the calendar.txt or calendar_dates.txt file.
    @CodedAt("serviceId")
    public let serviceID: String

    /// The shape_id field contains an ID that defines a shape for the trip.
    /// This value is referenced from the shapes API.
    @CodedAt("shapeId")
    public let shapeID: String

    @CodedBy(String.NillifyEmptyString())
    public let timeZone: String?

    /// Contains the text that appears in schedules and sign boards to identify the trip to passengers.
    ///
    /// For example: to identify train numbers for commuter rail trips. If riders do not commonly
    /// rely on trip names, this field may be blank. A short name, if provided, should uniquely
    /// identify a trip within a service day; it should not be used for destination names or
    /// limited/express designations.
    @CodedAt("tripShortName") @CodedBy(String.NillifyEmptyString())
    public let shortName: String?

    /// Contains the text that appears on a sign that identifies the trip's destination to passengers.
    ///
    /// Use this field to distinguish between different patterns of service in the same route.
    @CodedAt("tripHeadsign")
    public let headsign: String?
}

extension Trip {
    // MARK: - Route Descriptions

    /// A 'best effort' determination of the headsign for this `Trip`'s route.
    public var routeHeadsign: String {
        let bestShortName = routeShortName /*?? route.shortName*/
        let headsign = self.headsign

        return [bestShortName, headsign].compactMap { $0 }.joined(separator: " - ")
    }
}
