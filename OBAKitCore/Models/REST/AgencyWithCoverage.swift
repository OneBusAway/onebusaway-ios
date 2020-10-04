//
//  AgencyWithCoverage.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation
import MapKit

public class AgencyWithCoverage: NSObject, Identifiable, Decodable, HasReferences {
    public var id: String {
        return agencyID
    }

    public let agencyID: String
    public var agency: Agency!
    public let region: MKCoordinateRegion
    public private(set) var regionIdentifier: Int?

    private enum CodingKeys: String, CodingKey {
        case agencyID = "agencyId"
        case lat, latSpan, lon, lonSpan
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        agencyID = try container.decode(String.self, forKey: .agencyID)

        let lat = try container.decode(Double.self, forKey: .lat)
        let lon = try container.decode(Double.self, forKey: .lon)
        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)

        let latSpan = try container.decode(Double.self, forKey: .latSpan)
        let lonSpan = try container.decode(Double.self, forKey: .lonSpan)

        region = MKCoordinateRegion(center: coordinate, latitudinalMeters: latSpan, longitudinalMeters: lonSpan)
    }

    public func loadReferences(_ references: References, regionIdentifier: Int?) {
        agency = references.agencyWithID(agencyID)
        self.regionIdentifier = regionIdentifier
    }

    public override var debugDescription: String {
        var descriptionBuilder = DebugDescriptionBuilder(baseDescription: super.debugDescription)
        descriptionBuilder.add(key: "agency", value: agency)
        descriptionBuilder.add(key: "regionIdentifier", value: regionIdentifier)
        return descriptionBuilder.description
    }
}
