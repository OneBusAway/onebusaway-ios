//
//  Stop.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 10/21/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import CoreLocation

public enum WheelchairBoarding: String, Decodable {
    case accessible
    case notAccessible
    case unknown

    public init(from decoder: Decoder) throws {
        let val = try decoder.singleValueContainer().decode(String.self)
        self = WheelchairBoarding(rawValue: val) ?? .unknown
    }
}

@objc(OBAStopLocationType)
public enum StopLocationType: Int, Decodable {
    /// Stop. A location where passengers board or disembark from a transit vehicle.
    case stop

    /// Station. A physical structure or area that contains one or more stop.
    case station

    /// Station Entrance/Exit. A location where passengers can enter or exit a station from the street. The stop entry must also specify a parent_station value referencing the stop ID of the parent station for the entrance.
    case stationEntrance

    case unknown

    public init(from decoder: Decoder) throws {
        let val = try decoder.singleValueContainer().decode(Int.self)
        self = StopLocationType(rawValue: val) ?? .unknown
    }
}

public class Stop: NSObject, Decodable {

    /// The stop_code field contains a short piece of text or a number that uniquely identifies the stop for passengers.
    ///
    /// Stop codes are often used in phone-based transit information systems or printed on stop signage to
    /// make it easier for riders to get a stop schedule or real-time arrival information for a particular stop.
    /// The stop_code field contains short text or a number that uniquely identifies the stop for passengers.
    /// The stop_code can be the same as stop_id if it is passenger-facing. This field should be left blank
    /// for stops without a code presented to passengers.
    let code: String

    /// A cardinal direction: N, E, S, W.
    let direction: String?

    /// The stop_id field contains an ID that uniquely identifies a stop, station, or station entrance.
    ///
    /// Multiple routes may use the same stop. The stop_id is used by systems as an internal identifier
    /// of this record (e.g., primary key in database), and therefore the stop_id must be dataset unique.
    let id: String

    /// The coordinates of the stop.
    let location: CLLocation

    /// Identifies whether this stop represents a stop, station, or station entrance.
    let locationType: StopLocationType

    /// A human-readable name for this stop.
    let name: String

    /// A list of route IDs served by this stop.
    ///
    /// Route IDs correspond to values in References.
    let routeIDs: [String]

    /// Denotes the availability of wheelchair boarding at this stop.
    let wheelchairBoarding: WheelchairBoarding

    private enum CodingKeys: String, CodingKey {
        case code
        case direction
        case id
        case lat
        case lon
        case locationType
        case name
        case routeIDs = "routeIds"
        case wheelchairBoarding
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        code = try container.decode(String.self, forKey: .code)
        direction = ModelHelpers.nilifyBlankValue(try container.decode(String.self, forKey: .direction))
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)

        let lat = try container.decode(Double.self, forKey: .lat)
        let lon = try container.decode(Double.self, forKey: .lon)
        location = CLLocation(latitude: lat, longitude: lon)

        locationType = try container.decode(StopLocationType.self, forKey: .locationType)
        routeIDs = try container.decode([String].self, forKey: .routeIDs)
        wheelchairBoarding = try container.decode(WheelchairBoarding.self, forKey: .wheelchairBoarding)
    }
}
