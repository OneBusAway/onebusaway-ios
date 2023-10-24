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

public struct AgencyWithCoverage: Identifiable, Codable, Hashable {
    public let id: String
    let latitude: Double
    let longitude: Double
    let latitudeSpan: Double
    let longitudeSpan: Double

    public var region: MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            span: MKCoordinateSpan(latitudeDelta: latitudeSpan, longitudeDelta: longitudeSpan)
        )
    }

    internal enum CodingKeys: String, CodingKey {
        case id = "agencyId"
        case latitude = "lat"
        case longitude = "lon"
        case latitudeSpan = "latSpan"
        case longitudeSpan = "lonSpan"
    }
}
