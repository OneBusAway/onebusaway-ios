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
import MetaCodable

@Codable
public struct AgencyWithCoverage: Identifiable, Hashable /*, HasReferences*/ {
    @CodedAt("agencyId")
    public let id: String

    @CodedAt("lat")
    let latitude: Double

    @CodedAt("lon")
    let longitude: Double

    @CodedAt("latSpan")
    let latitudeSpan: Double

    @CodedAt("lonSpan")
    let longitudeSpan: Double

    public var region: MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            span: MKCoordinateSpan(latitudeDelta: latitudeSpan, longitudeDelta: longitudeSpan)
        )
    }
//    public var agency: Agency!

//    public private(set) var regionIdentifier: Int?

//    public func loadReferences(_ references: References, regionIdentifier: Int?) {
//        agency = references.agencyWithID(agencyID)
//        self.regionIdentifier = regionIdentifier
//    }
}
