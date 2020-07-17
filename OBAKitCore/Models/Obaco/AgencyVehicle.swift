//
//  AgencyVehicle.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// A search result for partial-match searches for vehicles by ID. Part of the Obaco service.
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
