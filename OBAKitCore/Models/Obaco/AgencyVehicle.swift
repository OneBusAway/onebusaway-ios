//
//  AgencyVehicle.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/10/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

public class AgencyVehicle: NSObject, Decodable {
    public let agencyID: String
    public let agencyName: String
    public let vehicleID: String?

    private enum CodingKeys: String, CodingKey {
        case agencyID = "id"
        case agencyName = "name"
        case vehicleID = "vehicle_id"
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        agencyID = try container.decode(String.self, forKey: .agencyID)
        agencyName = try container.decode(String.self, forKey: .agencyName)
        vehicleID = try container.decodeIfPresent(String.self, forKey: .vehicleID)
    }
}
