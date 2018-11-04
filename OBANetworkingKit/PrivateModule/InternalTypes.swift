//
//  InternalTypes.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 10/20/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
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

    convenience init<K>(container: KeyedDecodingContainer<K>, key: K) throws where K: CodingKey {
        let locationModel = try container.decode(LocationModel.self, forKey: key)
        self.init(latitude: locationModel.latitude, longitude: locationModel.longitude)
    }
}

extension DictionaryDecoder {
    public class func restApiServiceDecoder() -> DictionaryDecoder {
        let decoder = DictionaryDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970

        return decoder
    }

    public class func decodeModels<T>(_ entries: [[String: Any]], type: T.Type) throws -> [T] where T: Decodable {
        let decoder = DictionaryDecoder.restApiServiceDecoder()

        let models = try entries.compactMap { dict -> T? in
            return try decoder.decode(type, from: dict)
        }

        return models
    }
}
