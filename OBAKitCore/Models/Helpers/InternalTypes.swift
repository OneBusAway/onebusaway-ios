//
//  InternalTypes.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation

public struct LocationModel: Codable, Hashable {
    public let latitude: Double
    public let longitude: Double

    enum CodingKeys: String, CodingKey {
        case latitude = "lat"
        case longitude = "lon"
    }
}

#if canImport(CoreLocation)
import CoreLocation

extension LocationModel {
    public var coordinates: CLLocationCoordinate2D {
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    public var location: CLLocation {
        return CLLocation(latitude: latitude, longitude: longitude)
    }
}
#endif

extension JSONDecoder {
    class var obacoServiceDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return decoder
    }

    class func RESTDecoder(regionIdentifier: Int? = nil) -> JSONDecoder {
        let decoder = JSONDecoder()
        if let regionIdentifier = regionIdentifier {
            decoder.userInfo = [References.regionIdentifierUserInfoKey: regionIdentifier]
        }
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}
