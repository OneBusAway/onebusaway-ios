//
//  InternalTypes.swift
//  OBAKit
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

    convenience init?<K>(container: KeyedDecodingContainer<K>, key: K) throws where K: CodingKey {
        guard let locationModel = try container.decodeIfPresent(LocationModel.self, forKey: key) else {
            return nil
        }

        self.init(latitude: locationModel.latitude, longitude: locationModel.longitude)
    }
}

extension CodingUserInfoKey {
    public static let references: CodingUserInfoKey = CodingUserInfoKey(rawValue: "references")!
}

extension DictionaryDecoder {
    public class func restApiServiceDecoder() -> DictionaryDecoder {
        let decoder = DictionaryDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970

        return decoder
    }

    public class func decodeModels<T>(_ entries: [[String: Any]], references: References?, type: T.Type) throws -> [T] where T: Decodable {
        let decoder = DictionaryDecoder.restApiServiceDecoder()

        if let references = references {
            decoder.userInfo = [CodingUserInfoKey.references: references]
        }

        let models = try entries.compactMap { dict -> T? in
            return try decoder.decode(type, from: dict)
        }

        return models
    }

    public class func decodeRegionsFileData(_ data: Data) -> [Region] {
        // swiftlint:disable force_cast force_try
        let regionsJSON = try! JSONSerialization.jsonObject(with: data, options: []) as! [AnyHashable: Any]
        let dataNode = regionsJSON["data"] as! [AnyHashable: Any]
        let listNode = dataNode["list"] as! [[String: Any]]
        return try! DictionaryDecoder.decodeModels(listNode, references: nil, type: Region.self)
        // swiftlint:enable force_cast force_try
    }
}

extension JSONDecoder {
    public class func obacoServiceDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        return decoder
    }
}
