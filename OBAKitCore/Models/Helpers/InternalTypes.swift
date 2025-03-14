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

struct LocationModel: Codable {
    let latitude: Double
    let longitude: Double

    enum CodingKeys: String, CodingKey {
        case latitude = "lat"
        case longitude = "lon"
    }
}

extension CLLocation {
    convenience init(locationModel: LocationModel) {
        self.init(latitude: locationModel.latitude, longitude: locationModel.longitude)
    }

    convenience init?<K>(container: KeyedDecodingContainer<K>, key: K) throws where K: CodingKey {
        guard let locationModel = try container.decodeIfPresent(LocationModel.self, forKey: key) else {
            return nil
        }

        self.init(latitude: locationModel.latitude, longitude: locationModel.longitude)
    }
}

extension JSONDecoder {
    class var obacoServiceDecoder: JSONDecoder {
            let decoder = JSONDecoder()

            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let dateString = try container.decode(String.self)

                let formats = [
                    "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX", // format with milliseconds
                    "yyyy-MM-dd'T'HH:mm:ssXXXXX"      // format without milliseconds
                ]

                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0)

                for format in formats {
                    formatter.dateFormat = format
                    if let date = formatter.date(from: dateString) {
                        return date
                    }
                }

                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date format: \(dateString)")
            }

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
